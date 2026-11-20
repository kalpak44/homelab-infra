#!/usr/bin/env python3
"""Back up operator inputs in Vault and restore local/Actions copies."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SECRET = "secret/data/homelab-infra-secrets"
NAME = re.compile(r"^[A-Z_][A-Z0-9_]*$")


def key(name):
    return name.lower().replace("_", "-")


def local_values():
    path = ROOT / ".env"
    names = re.findall(r"^(?:export\s+)?([A-Z_][A-Z0-9_]*)=", path.read_text(), re.M)
    code = "import json,os,sys; print(json.dumps({n:os.environ[n] for n in sys.argv[1:]}))"
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", 'set -a; source "$1"; shift; python3 -c "$@"',
         "bootstrap-secrets", str(path), code, *names],
        cwd=ROOT, capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError("Could not load root .env; no secret values were logged")
    return json.loads(result.stdout)


def required_secrets():
    names = set()
    for path in (ROOT / ".github/workflows").glob("*.yml"):
        names.update(re.findall(r"secrets\.([A-Z][A-Z0-9_]*)", path.read_text()))
    return names - {"GITHUB_TOKEN"}


class Vault:
    def __init__(self, env):
        self.addr = env.get("VAULT_ADDR", "").rstrip("/")
        if not self.addr.startswith("https://"):
            raise RuntimeError("VAULT_ADDR must be an HTTPS URL")
        self.token = env.get("VAULT_TOKEN", "")
        self.created_token = False
        if not self.token and env.get("VAULT_USERNAME") and env.get("VAULT_PASSWORD"):
            user = urllib.parse.quote(env["VAULT_USERNAME"], safe="")
            response = self.request("POST", "auth/userpass/login/" + user,
                                    {"password": env["VAULT_PASSWORD"]})
            self.token = response["auth"]["client_token"]
            self.created_token = True
        if not self.token:
            cached = Path.home() / ".vault-token"
            if cached.exists():
                self.token = cached.read_text().strip()
        if not self.token:
            raise RuntimeError("Provide VAULT_TOKEN or VAULT_USERNAME/VAULT_PASSWORD")

    def request(self, method, path, payload=None, missing_ok=False):
        body = None if payload is None else json.dumps(payload).encode()
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["X-Vault-Token"] = self.token
        request = urllib.request.Request(self.addr + "/v1/" + path, data=body,
                                         headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            if missing_ok and exc.code == 404:
                return None
            raise RuntimeError(f"Vault {method} {path} failed (HTTP {exc.code})") from None
        except (urllib.error.URLError, TimeoutError):
            raise RuntimeError("Vault connection failed; check DNS, network and TLS") from None

    def close(self):
        if self.created_token:
            self.request("POST", "auth/token/revoke-self", {})


def dotenv(values):
    rendered = {}
    for name, value in sorted(values.items()):
        if not NAME.fullmatch(name) or not isinstance(value, str):
            raise RuntimeError("Vault bootstrap record contains an invalid environment entry")
        # Actual newlines work in both shell double quotes and just's dotenv parser.
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
        rendered[name] = f'export {name}="{escaped}"'
    template = ROOT / ".env.example"
    lines = []
    if template.exists():
        for line in template.read_text().splitlines():
            match = re.match(r"^export ([A-Z_][A-Z0-9_]*)=", line)
            if match:
                if match[1] in rendered:
                    lines.append(rendered.pop(match[1]))
            else:
                lines.append(line)
    else:
        lines.append("# Restored from Vault; ignored by Git. Paths are relative to the repository root.")
    if rendered:
        lines.extend(["", "# Additional inputs restored from Vault.", *rendered.values()])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["store", "check", "restore-env", "sync-github"])
    parser.add_argument("--replace-existing", action="store_true",
                        help="allow replacing differing Vault values or the local .env")
    args = parser.parse_args()
    local = local_values() if args.action == "store" else {}
    env = {**local, **os.environ}
    vault = Vault(env)
    try:
        record = vault.request("GET", SECRET, missing_ok=args.action == "store")
        data = record["data"]["data"] if record else {}
        version = record["data"]["metadata"]["version"] if record else 0
        if args.action == "store":
            incoming = {key(name): value for name, value in local.items()}
            differing = sorted(name for name, value in incoming.items()
                               if name in data and data[name] != value)
            if differing and not args.replace_existing:
                raise RuntimeError("Vault already has different values for: " + ", ".join(differing)
                                   + "; review before using --replace-existing")
            combined = {**data, **incoming}
            if combined != data:
                vault.request("POST", SECRET, {"data": combined, "options": {"cas": version}})
            verified = vault.request("GET", SECRET)["data"]["data"]
            if any(verified.get(name) != value for name, value in incoming.items()):
                raise RuntimeError("Vault read-back verification failed")
            print(f"Verified {len(incoming)} local inputs in secret/homelab-infra-secrets")
            return

        values = {name.upper().replace("-", "_"): value for name, value in data.items()}
        if args.action == "restore-env":
            destination = ROOT / ".env"
            # Create exclusively unless replacing was explicitly requested; never follow symlinks.
            flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW
            flags |= os.O_TRUNC if args.replace_existing else os.O_EXCL
            content = dotenv(values)
            descriptor = os.open(destination, flags, 0o600)
            with os.fdopen(descriptor, "w") as output:
                os.fchmod(output.fileno(), 0o600)
                output.write(content)
            print(f"Restored {len(values)} variables into root .env (0600)")
            return

        required = required_secrets()
        missing = sorted(name for name in required if not values.get(name))
        if missing:
            raise RuntimeError("Not backed up in Vault: " + ", ".join(missing))
        print(f"All {len(required)} workflow secret inputs are present in Vault")
        if args.action == "check":
            return

        github_env = dict(os.environ)
        github_env["GH_TOKEN"] = values["GH_ADMIN_TOKEN"]
        for name in sorted(required):
            result = subprocess.run(
                ["gh", "secret", "set", name, "--repo", "kalpak44/homelab-infra"],
                input=values[name], text=True, capture_output=True, env=github_env,
            )
            if result.returncode:
                raise RuntimeError(f"GitHub secret update failed for {name}; re-run to finish")
        print(f"Synchronized {len(required)} Actions secrets from Vault")
    finally:
        vault.close()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as exc:
        # Exception values from external responses or file contents can contain credentials.
        message = str(exc) if isinstance(exc, RuntimeError) else type(exc).__name__
        print(f"error: {message}", file=sys.stderr)
        sys.exit(1)
