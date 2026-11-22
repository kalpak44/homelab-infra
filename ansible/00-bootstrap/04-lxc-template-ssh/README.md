# Key-only SSH in the LXC template

Writes the key-only sshd drop-in into the LXC template, so a new container accepts
only the operator key Terraform injects for root.

Prerequisites: 03-lxc-template.

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
| `LXC_TEMPLATE` | Ansible variable `lxc_template`. Default: `ubuntu-24.04-standard_24.04-2_amd64.tar.zst`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
