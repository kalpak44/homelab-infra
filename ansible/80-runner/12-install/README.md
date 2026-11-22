# Install GitHub Actions runner binaries

Install GitHub Actions runner binaries.

Prerequisites: 05-packages.

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
| `RUNNER_VERSION` | Ansible variable `runner_version`. Default: `2.338.2`. |
| `RUNNER_DIR` | Ansible variable `runner_dir`. Default: `/home/ubuntu/actions-runner`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
