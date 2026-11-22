# Register the Proxmox ACME account

Register the Proxmox ACME account.

Prerequisites: None.

From this directory:

```bash
# Edit .env; recreate it from .env.example if missing.
just apply
# For a host without the operator key yet:
just apply --ask-pass
```

The command loads only this directory’s `.env`. It does not read the root `.env`.

| Input | Purpose |
|-------|---------|
| `TARGET_HOST` | SSH target address. |
| `TARGET_USER` | SSH login user. |
| `TARGET_PASSWORD` | SSH/sudo password; only for a host without the operator key yet. |
| `SSH_PRIVATE_KEY` | Base64 operator key, from this `.env` or your shell; used when set. |
| `ACME_ACCOUNT` | Ansible variable `acme_account`. Default: `default`. |
| `ACME_DIRECTORY` | Ansible variable `acme_directory`. Default: `https://acme-v02.api.letsencrypt.org/directory`. |
| `LETSENCRYPT_EMAIL` | Ansible variable `letsencrypt_email`. Default: empty; fill before use. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
