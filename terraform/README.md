# Terraform

Provisions all long-lived infrastructure.

## Layout

```
terraform/
├── Justfile                 # deploy / destroy / list recipes
├── modules/                 # reusable primitives (not deployable on their own)
│   ├── proxmox-lxc/
│   └── proxmox-vm/          # clones from Proxmox VM template 9000
├── cloudflare/              # everything on the Cloudflare side
│   ├── dns/
│   │   ├── private/         # LAN-only *.internal A records (unproxied)
│   │   └── public/          # internet-facing records (Cloudflare-proxied)
│   └── shared/              # non-DNS Cloudflare resources (email routing)
└── proxmox/                 # LXCs + VMs on the Proxmox node
    ├── adguard-lxc/
    ├── vault-lxc/
    ├── postgres-lxc/
    ├── redis-lxc/
    ├── rabbitmq-lxc/
    ├── haproxy-lxc/
    ├── nfs-vm/
    ├── portainer-vm/
    └── k3s-cluster/         # two VMs (k3s-1, k3s-2)
```

Each leaf directory has `main.tf`, `variables.tf`, `providers.tf`, `versions.tf`, and a `backend.tf` pointing at its own
R2 key (`homelab/<layer>/<path>.tfstate`).

## Usage

```bash
just deploy  <layer> <resource>   # terraform init + apply
just destroy <layer> <resource>   # terraform init + destroy
just list                         # print every deployable resource dir
```

Examples:

```bash
just deploy cloudflare dns/private/adguard
just deploy proxmox    adguard-lxc
just destroy cloudflare shared/cloudflare-email
```

Via GitHub Actions: **Cloudflare - Deploy** / **Cloudflare - Destroy** / **Proxmox - Deploy** / **Proxmox - Destroy** -
pick the resource from the dropdown, one dispatch per resource.

## Environment variables

All layers need R2 backend credentials:

| Var                     | Purpose                           |
|-------------------------|-----------------------------------|
| `AWS_ACCESS_KEY_ID`     | R2 access key                     |
| `AWS_SECRET_ACCESS_KEY` | R2 secret                         |
| `AWS_ENDPOINT_URL_S3`   | R2 S3-compat endpoint             |
| `R2_BUCKET_NAME`        | bucket that holds tfstate objects |

Cloudflare layer:

| Var                           | Where used                     |
|-------------------------------|--------------------------------|
| `TF_VAR_cloudflare_api_token` | every cloudflare/ dir          |
| `TF_VAR_haproxy_public_ip`    | `cloudflare/dns/public/*` only |

Proxmox layer:

| Var                                                 | Where used                      |
|-----------------------------------------------------|---------------------------------|
| `TF_VAR_proxmox_endpoint`, `_username`, `_password` | proxmox provider auth           |
| `TF_VAR_ssh_public_key`                             | injected via cloud-init         |
| `TF_VAR_ssh_private_key`                            | proxmox provider SSH connection |

`TF_VAR_*` env vars are silently ignored by directories that don't declare the matching variable - this is why one
workflow can safely set them all.