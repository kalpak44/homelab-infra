# Create and start the runner VM

Create and start the runner VM.

Prerequisites: 05-vm-ssh-snippet and 06-cloud-image. Optional: only for remaining GitHub workflows.

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
| `RUNNER_ID` | Ansible variable `runner_id`. Default: `101`. |
| `RUNNER_IP` | Ansible variable `runner_ip`. Default: `192.168.1.101`. |
| `RUNNER_GW` | Ansible variable `runner_gw`. Default: `192.168.1.1`. |
| `RUNNER_STORAGE` | Ansible variable `runner_storage`. Default: `local-lvm`. |
| `CLOUD_IMAGE_DEST` | Ansible variable `cloud_image_dest`. Default: `/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
