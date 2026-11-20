# Grow the runner virtual disk

Grow the runner virtual disk.

Prerequisites: 01-vm; follow with 03-filesystem.

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
| `RUNNER_ID` | Ansible variable `runner_id`. Default: `101`. |
| `RUNNER_DISK_GB` | Ansible variable `runner_disk_gb`. Default: `20`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
