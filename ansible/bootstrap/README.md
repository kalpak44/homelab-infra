# Bootstrap – fresh Proxmox setup

Automates the one-time manual steps documented in the root [`README.md`](../../README.md#setup): creating the Terraform
user + role + API token, downloading base artifacts, provisioning the GitHub Actions runner VM, and issuing a Let's
Encrypt cert for the Proxmox web UI.

## Usage

From `ansible/`:

```bash
# SSH key auth (recommended - copy your key to the Proxmox node first with ssh-copy-id)
just bootstrap 192.168.1.50

# Password auth (fresh node, no keys yet - prompts for the password)
just bootstrap-pw 192.168.1.50
```

Both recipes accept an optional user (defaults to `root`).

## What each phase does

| File                       | What it does                                                                                                                                     |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| `01-proxmox-setup.yml`     | Create Terraform role + user + API token; enable snippet storage on `local`                                                                      |
| `02-proxmox-artifacts.yml` | Download Ubuntu 24.04 LXC template and patch it with SSH password-auth drop-in; create VM vendor-data snippet; download cloud image; create VM 9000 template |
| `03-runner-vm.yml`         | Create runner VM (id=101) with password auth; install ansible/terraform/just/gh; auto-register the GitHub Actions runner                         |
| `04-proxmox-tls.yml`       | Register Let's Encrypt ACME account, add Cloudflare DNS-01 plugin, order cert                                                                    |

`main.yml` runs all four in order. Each is also runnable standalone:

```bash
ansible-playbook -i "192.168.1.50," -u root bootstrap/02-proxmox-artifacts.yml \
  -e "host_password=$HOST_PASSWORD"
ansible-playbook -i "192.168.1.50," -u root bootstrap/04-proxmox-tls.yml \
  -e "letsencrypt_email=$LETSENCRYPT_EMAIL" \
  -e "cloudflare_api_token=$CLOUDFLARE_API_TOKEN"
```

## Required inputs

The Justfile recipes read these from your shell:

| Env var                | Used by  | Notes                                                                                          |
|------------------------|----------|------------------------------------------------------------------------------------------------|
| `HOST_PASSWORD`        | Phase 3  | Password baked into the runner VM (ubuntu + root); also used for all LXC/VM services later    |
| `LETSENCRYPT_EMAIL`    | Phase 4  | Email registered with Let's Encrypt                                                            |
| `CLOUDFLARE_API_TOKEN` | Phase 4  | Same token used by the main workflows (Zone:DNS:Edit)                                          |
| `PROXMOX_DOMAIN`       | Phase 4  | FQDN of the Proxmox node (must already resolve via DNS). Default: `proxmox.internal.pavel-usanli.online` |
| `GITHUB_TOKEN`         | Phase 3  | PAT with `repo` scope – used to auto-register the runner. Skipped if unset.                   |
| `GITHUB_REPO`          | Phase 3  | `owner/repo` slug (e.g. `pnueli/homelab-infra`). Skipped if unset.                            |

Phase 4 fails cleanly if its inputs are missing – earlier phases are already applied and safe.
Phase 3 runner registration is skipped if `GITHUB_TOKEN` / `GITHUB_REPO` are not set; the runner VM is still created.

## Idempotency

Every task in every phase is safe to re-run:

- `pveum role/user/token add` — `already exists` guard on stderr; role privileges synced on every re-run
- ACL grants — pre-checked via `pveum acl list` before applying
- `pveam download` — uses `creates:`
- LXC template patch — checks for `etc/ssh/sshd_config.d/99-password-login.conf` inside the archive before repacking
- VM vendor-data snippet — idempotent `copy` (overwrite is safe)
- `qm create 9000` / `qm create 101` — skipped if the VM already exists (`qm status` probe)
- VM cicustom — pre-checked via `qm config` before applying
- `pvenode acme account/plugin` — probed via `pvenode acme account list` / `plugin list`
- Let's Encrypt cert order — skipped if the current cert is valid for more than 30 days

Only the API token from phase 1 is a one-shot output – save it the first time you run bootstrap; you can't retrieve it
later.

## LXC template SSH patch

Phase 2 patches the downloaded LXC template archive to include a sshd drop-in
(`/etc/ssh/sshd_config.d/99-password-login.conf`) that enables `PasswordAuthentication yes` and `PermitRootLogin yes`.
This is required so Ansible can reach freshly provisioned LXCs via password auth before any playbook has run.

If the template was already downloaded before the bootstrap was run (or was re-downloaded), re-run phase 2 — it is
idempotent and will repack only if the drop-in is missing.

## What's still manual after bootstrap

- **Populate GitHub secrets** listed in the root README under _Setup → 3._ (Terraform token from phase 1's output goes
  in as `PROXMOX_PASSWORD`).