# Download the Ubuntu VM cloud image

Download the Ubuntu VM cloud image.

Prerequisites: None.

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
| `CLOUD_IMAGE_URL` | Ansible variable `cloud_image_url`. Default: `https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img`. |
| `CLOUD_IMAGE_DEST` | Ansible variable `cloud_image_dest`. Default: `/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img`. |

[Ansible stages](../../README.md) · [Setup guide](<../../../docs/1 - Bootstrap.md>)
