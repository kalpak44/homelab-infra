# Install local operator Terraform on the runner

Install local operator Terraform on the runner.

Prerequisites: 05-packages. Operator tooling also used by the dedicated, validated AI maintenance controller.

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
| `TERRAFORM_VERSION` | Ansible variable `terraform_version`. Default: `1.17.2`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
