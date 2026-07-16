# Bootstrap - fresh Proxmox setup

Automates the one-time manual steps documented in the root [`README.md`](../../README.md#setup): creating the Terraform user + role + API token, downloading base artifacts, provisioning the GitHub Actions runner VM, and issuing a Let's Encrypt cert for the Proxmox web UI.

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

| File | Manual step it replaces |
|---|---|
| `01-proxmox-setup.yml` | Create Terraform role + user + API token; enable snippet storage on `local` |
| `02-proxmox-artifacts.yml` | Download Ubuntu 24.04 LXC template; download Ubuntu cloud image; create template VM 9000 |
| `03-runner-vm.yml` | Create runner VM (id=101), install ansible/terraform/just, print manual runner-registration steps |
| `04-proxmox-tls.yml` | Register Let's Encrypt ACME account, add Cloudflare DNS-01 plugin, order cert |

`main.yml` runs all four in order. Each is also runnable standalone:

```bash
ansible-playbook -i "192.168.1.50," -u root bootstrap/01-proxmox-setup.yml
ansible-playbook -i "192.168.1.50," -u root bootstrap/04-proxmox-tls.yml
```

## Required inputs

The Justfile recipes read these from your shell:

| Env var | Used by | Notes |
|---|---|---|
| `LETSENCRYPT_EMAIL` | Phase 4 | Email registered with Let's Encrypt |
| `CLOUDFLARE_API_TOKEN` | Phase 4 | Same token used by the main workflows (Zone:DNS:Edit) |
| `PROXMOX_DOMAIN` | Phase 4 | FQDN of the Proxmox node (must already resolve to it via DNS). Default: `proxmox.internal.pavel-usanli.online` |
| `SSH_PUBLIC_KEY_FILE` | Phase 3 | Path to your local SSH pubkey (default: `~/.ssh/id_ed25519.pub`). Injected into the runner VM so you can SSH in afterwards. |

If Phase 4's inputs are missing, that phase fails cleanly and the earlier phases are already applied - safe.

## Idempotency

Every task in every phase is safe to re-run:
- `pveum role/user/token add` - trapped via `already exists` on stderr
- `pveam download` - uses `creates:`
- `qm create 9000` / `qm create 101` - skipped if the VM already exists (`qm status` probe)
- `pvenode acme account/plugin` - probed via `pvenode acme account list` / `plugin list`

Only the API token from phase 1 is one-shot output - save it the first time you run bootstrap; you can't retrieve it later.

## What's still manual after bootstrap

- **Register the GitHub Actions runner** on VM 101 (needs a one-time token from the repo Settings page - Phase 3 prints the exact steps).
- **Populate GitHub secrets** listed in the root README under _Setup → 3._ (Terraform token from phase 1's output goes in as `PROXMOX_PASSWORD`).