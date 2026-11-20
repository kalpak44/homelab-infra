# Issue the Proxmox TLS certificate

Issue the Proxmox TLS certificate.

Prerequisites: 01-acme-account and 02-acme-cloudflare; the hostname must resolve to Proxmox.

From this directory:

```bash
# Edit .env; recreate it from .env.example if missing.
just apply
# For a host without SSH keys:
just apply --ask-pass
```

The command loads only this directory’s `.env`. It does not read the root `.env`.

| Input | Purpose |
|-------|---------|
| `TARGET_HOST` | SSH target address. |
| `TARGET_USER` | SSH login user. |
| `TARGET_PASSWORD` | SSH/sudo password; optional with SSH keys or prompts. |
| `ACME_ACCOUNT` | Ansible variable `acme_account`. Default: `default`. |
| `PROXMOX_DOMAIN` | Ansible variable `proxmox_domain`. Default: `proxmox.internal.pavel-usanli.online`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
