# Create the Proxmox VM template

Create the Proxmox VM template.

Prerequisites: 05-vm-ssh-snippet and 06-cloud-image.

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
| `TEMPLATE_VM_ID` | Ansible variable `template_vm_id`. Default: `9000`. |
| `TEMPLATE_VM_NAME` | Ansible variable `template_vm_name`. Default: `ubuntu-2404-template`. |
| `TEMPLATE_STORAGE` | Ansible variable `template_storage`. Default: `local-lvm`. |
| `CLOUD_IMAGE_DEST` | Ansible variable `cloud_image_dest`. Default: `/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
