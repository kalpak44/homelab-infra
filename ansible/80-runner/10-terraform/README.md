# Install local operator Terraform on the runner

Install local operator Terraform on the runner.

Prerequisites: 05-packages. Optional operator tooling; GitHub Actions does not run Terraform.

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
| `TERRAFORM_VERSION` | Ansible variable `terraform_version`. Default: `1.17.2`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
