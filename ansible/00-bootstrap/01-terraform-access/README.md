# Terraform access to Proxmox

Creates the Terraform role, `terraform@pve` user, ACL grants, and API token.
Each operation has its own file under `tasks/`; `playbook.yml` runs them in order.

```bash
cd ansible/00-bootstrap/01-terraform-access
# Edit .env with the Proxmox address and root SSH login.
just apply
# Fresh Proxmox with password login:
just apply --ask-pass
```

The dedicated Justfile loads this directory's `.env` only. `.env.example` is its
checked-in template. `TARGET_HOST` is the Proxmox IP, `TARGET_USER` defaults to `root`,
and `SSH_PRIVATE_KEY` (base64, from this `.env` or your shell) logs in by key. Only a node
that does not have the key yet needs `TARGET_PASSWORD` or `--ask-pass`.

The output prints `PROXMOX_USERNAME=terraform@pve!terraform` and the new API token's
`value`. Save that value as `PROXMOX_PASSWORD` for local Terraform. Reapplying keeps
existing access and prints the token identity; Proxmox only reveals its secret once.
The component never creates a replacement token just to print credentials.

[Setup sequence](<../../../docs/1 - Bootstrap.md>) · [Next: Vault](<../../../docs/3 - Vault container.md>)
