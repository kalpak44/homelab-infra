# Enable password SSH in the LXC template

Enable password SSH in the LXC template.

Prerequisites: 03-lxc-template.

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
| `LXC_TEMPLATE` | Ansible variable `lxc_template`. Default: `ubuntu-24.04-standard_24.04-2_amd64.tar.zst`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
