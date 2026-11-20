# Configure runner SSH access

Configure runner SSH access.

Prerequisites: 01-vm. Controller needs passlib for password hashing.

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
| `HOST_PASSWORD` | Ansible variable `host_password`. Default: empty; fill before use. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
