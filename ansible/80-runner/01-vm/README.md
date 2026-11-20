# Create and start the runner VM

Create and start the runner VM.

Prerequisites: 05-vm-ssh-snippet and 06-cloud-image. Optional: only for remaining GitHub workflows.

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
| `RUNNER_IP` | Ansible variable `runner_ip`. Default: `192.168.1.101`. |
| `RUNNER_GW` | Ansible variable `runner_gw`. Default: `192.168.1.1`. |
| `RUNNER_STORAGE` | Ansible variable `runner_storage`. Default: `local-lvm`. |
| `CLOUD_IMAGE_DEST` | Ansible variable `cloud_image_dest`. Default: `/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img`. |
| `HOST_PASSWORD` | Ansible variable `host_password`. Default: empty; fill before use. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
