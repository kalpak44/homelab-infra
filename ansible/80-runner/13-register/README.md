# Register and start the GitHub Actions runner

Register and start the GitHub Actions runner.

Prerequisites: 12-install. PAT must allow runner administration for the target repository.

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
| `RUNNER_DIR` | Ansible variable `runner_dir`. Default: `/home/ubuntu/actions-runner`. |
| `GITHUB_TOKEN` | Ansible variable `github_token`. Default: empty; fill before use. |
| `GITHUB_REPO` | Ansible variable `github_repo`. Default: `kalpak44/homelab-infra`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
