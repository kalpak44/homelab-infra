#!/usr/bin/env python3
# Proves every CrowdSec file here reaches the chart. A file missing from kustomization.yaml
# or helmrelease.yaml's valuesFrom is silently never loaded, and kustomize passes either way.
#
#   python3 gitops/clusters/homelab/infrastructure/crowdsec/check.py
#
# Needs PyYAML (apt: python3-yaml). Exits non-zero and names each problem.
import hashlib
import pathlib
import re
import sys

import yaml

HERE = pathlib.Path(__file__).resolve().parent

# Directory -> the ConfigMap kustomization.yaml builds from it, and where the chart wants it.
LAYOUT = {
    "config": ("crowdsec-src-config-files", "config."),
    "parsers": ("crowdsec-src-parsers", "config.parsers.s02-enrich."),
    "scenarios": ("crowdsec-src-scenarios", "config.scenarios."),
    "appsec-rules": ("crowdsec-src-appsec-rules", "appsec.rules."),
    "appsec-configs": ("crowdsec-src-appsec-configs", "appsec.configs."),
}

problems = []
kust = yaml.safe_load((HERE / "kustomization.yaml").read_text())
hr = yaml.safe_load((HERE / "helmrelease.yaml").read_text())
generators = {g["name"]: g for g in kust.get("configMapGenerator", [])}
values_from = {(v["name"], v["valuesKey"]): v for v in hr["spec"].get("valuesFrom", [])}
parsed = {}

for d, (cm, prefix) in LAYOUT.items():
    on_disk = sorted(p.name for p in (HERE / d).iterdir() if p.is_file())
    gen = generators.get(cm)
    if gen is None:
        problems.append(f"kustomization.yaml has no ConfigMap {cm} for {d}/")
        continue
    if gen.get("options", {}).get("labels", {}).get("reconcile.fluxcd.io/watch") != "Enabled":
        problems.append(f"{cm} lacks the reconcile.fluxcd.io/watch label")
    listed = sorted(pathlib.PurePath(f).name for f in gen.get("files", []))
    for name in sorted(set(on_disk) - set(listed)):
        problems.append(f"{d}/{name} is not listed under {cm} in kustomization.yaml")
    for name in sorted(set(listed) - set(on_disk)):
        problems.append(f"kustomization.yaml lists {d}/{name}, which does not exist")
    for name in on_disk:
        v = values_from.get((cm, name))
        want = prefix + name.replace(".", "\\.")
        if v is None:
            problems.append(f"{d}/{name} has no valuesFrom entry in helmrelease.yaml")
        elif v.get("targetPath") != want or v.get("literal") is not True:
            problems.append(f"{d}/{name}: valuesFrom needs targetPath '{want}' and literal: true")
        try:
            docs = list(yaml.safe_load_all((HERE / d / name).read_text()))
        except yaml.YAMLError as e:
            problems.append(f"{d}/{name} does not parse: {e}")
            continue
        parsed[(d, name)] = docs[0]
        if d in ("scenarios", "appsec-rules", "parsers") and not docs[0].get("name"):
            problems.append(f"{d}/{name} has no name:")

for (cm, key) in values_from:
    if not any(cm == c for c, _ in LAYOUT.values()):
        continue
    d = next(d for d, (c, _) in LAYOUT.items() if c == cm)
    if not (HERE / d / key).is_file():
        problems.append(f"valuesFrom names {d}/{key}, which does not exist")

# A scenario no profile names creates alerts and never a decision.
profiles = (HERE / "config/profiles.yaml").read_text()
for (d, fname), doc in sorted(parsed.items()):
    if d == "scenarios" and doc.get("name") and f'"{doc["name"]}"' not in profiles:
        problems.append(f"scenarios/{fname}: no profile in config/profiles.yaml names {doc['name']}")

# An AppSec rule no config lists is loaded and never evaluated.
listed_rules = set()
for (d, fname), doc in parsed.items():
    if d == "appsec-configs":
        listed_rules |= set(doc.get("inband_rules", [])) | set(doc.get("outofband_rules", []))
for (d, fname), doc in sorted(parsed.items()):
    if d == "appsec-rules" and doc.get("name") and doc["name"] not in listed_rules:
        problems.append(f"appsec-rules/{fname}: {doc['name']} is in no appsec-configs/ rule list")

# The agent pods reload the blocklist only when this annotation changes.
digest = hashlib.sha256((HERE / "blocked-ips.txt").read_bytes()).hexdigest()
annotation = hr["spec"]["values"]["agent"]["podAnnotations"][
    "homelab.pavel-usanli.online/blocked-ips-sha256"]
if annotation != digest:
    problems.append(f"blocked-ips-sha256 in helmrelease.yaml is {annotation}, file is {digest}")
for n, line in enumerate((HERE / "blocked-ips.txt").read_text().splitlines(), 1):
    line = line.strip()
    if line and not line.startswith("#") and not re.fullmatch(r"[0-9a-fA-F:.]+(/\d+)?", line):
        problems.append(f"blocked-ips.txt:{n} is not a bare address: {line}")

for p in problems:
    print(f"FAIL {p}")
print(f"{len(problems)} problem(s)" if problems else "ok")
sys.exit(1 if problems else 0)
