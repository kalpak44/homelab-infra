# Configure runner SSH access

Configure runner SSH access.

Prerequisites: 01-vm. Authorizes the operator key for root and ubuntu, then turns password
login off. The first run on a new VM still needs `--ask-pass` only if its key is missing.

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

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
