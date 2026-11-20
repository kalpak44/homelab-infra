# 3. Provision the Vault container

Start after [the LXC template](<2 - LXC template.md>). This step creates the Vault host.
Vault installation and secret storage happen in [step 6](<6 - Vault secrets.md>) once
DNS and k3s are ready, because the current Vault role includes Kubernetes integration.

## 1. Prepare local Terraform inputs

If the root `.env` does not exist, copy `.env.example` to `.env` and set its permissions
to `600`. Keep any existing local values when editing it. Terraform recipes still
load this root environment; bootstrap parts use their separate environments.

Fill these inputs:

| Input | Value or source |
|-------|-----------------|
| `R2_ACCESS_KEY_ID` | Cloudflare R2 state-bucket access key |
| `R2_SECRET_ACCESS_KEY` | Matching R2 secret |
| `R2_ENDPOINT` | R2 S3 API endpoint for your Cloudflare account |
| `R2_BUCKET_NAME` | Existing state bucket name |
| `PROXMOX_ENDPOINT` | Proxmox HTTPS API, for example `https://192.168.1.50:8006` |
| `PROXMOX_USERNAME` | `terraform@pve!terraform`, printed by bootstrap |
| `PROXMOX_PASSWORD` | New API token value printed by bootstrap |
| `HOST_PASSWORD` | Initial guest password used by the current provisioning setup |
| `SSH_PUBLIC_KEY` | Operator public SSH key installed in the guest |
| `SSH_PRIVATE_KEY` | Matching key when required by the Proxmox provider SSH connection |

See [Terraform inputs](../terraform/README.md) for the complete environment reference.

## 2. Review the container definition

`terraform/proxmox/vault-lxc/` currently creates:

- LXC ID `201`, hostname `vault`, address `192.168.1.3/24`, gateway `192.168.1.1`.
- One CPU, 256 MB RAM, and an 8 GB root disk.
- The Ubuntu LXC archive prepared in the previous step.

Check these values against your LAN and available capacity. If you change the
address, also update `ansible/inventories/hosts.yml` and the internal DNS record.
Keep `lxc_template_file_id` consistent with the archive you downloaded and patched.

## 3. Apply the Terraform resource

From the repository root:

```bash
just --justfile terraform/Justfile deploy proxmox vault-lxc
```

This initializes the resource's own R2 backend and applies its container definition.
It does not install or initialize Vault. The current `deploy` recipe applies with
`-auto-approve`, so review the resource files and local inputs before running it.

## 4. Check the host

```bash
ssh root@192.168.1.50 'pct status 201'
ssh root@192.168.1.3 'hostname'
```

The container should be running and reachable as `vault`. Use the initial guest
password or your installed SSH key.

Next: [Networking](<4 - Networking.md>), then [storage and k3s](<5 - Storage and k3s.md>).
After those prerequisites, [step 6](<6 - Vault secrets.md>) configures Vault and stores secrets.
