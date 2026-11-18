# Terraform

Provisions all long-lived infrastructure.

## Layout

```
terraform/
├── Justfile                 # deploy / destroy / output / list recipes
├── modules/                 # reusable primitives (not deployable on their own)
│   ├── proxmox-lxc/
│   └── proxmox-vm/          # clones from Proxmox VM template 9000
├── cloudflare/              # everything on the Cloudflare side
│   ├── tunnels/             # one state per tunnel: ingress + every record pointing at it
│   │   ├── homelab/         # k3s tunnel, public hostnames in all zones, SaaS, WARP
│   │   └── mihal/           # WARP-only SSH to mihal-lxc
│   └── zones/               # one dir per zone, one state per concern
│       ├── blocked-ips.txt  # read by every zone's edge/
│       ├── pavel-usanli.online/
│       │   ├── edge/        # WAF, apex→www redirect, zone settings
│       │   ├── email/       # contact@ routing, Mailjet senders, SPF/DKIM/DMARC
│       │   └── internal/    # every *.internal A record, one map
│       ├── proklinator.online/
│       │   ├── edge/        # WAF: scanners, rate limit, blocklist
│       │   └── email/       # sales@ → Gmail forwarding
│       └── workspaced.online/
│           ├── edge/        # WAF, zone settings, Domain Connect key
│           └── email/       # contact@, sales@, support@, investor@ → Gmail forwarding
├── proxmox/                 # LXCs + VMs on the Proxmox node, one dir each
│   ├── adguard-lxc/  vault-lxc/  postgres-lxc/  redis-lxc/  cloudflared-lxc/
│   ├── nocobase-lxc/  mihal-lxc/  prometheus-lxc/  grafana-lxc/  rustfs-lxc/
│   ├── nfs-vm/  portainer-vm/
│   └── k3s-cluster/         # two VMs (k3s-1, k3s-2)
├── github/                  # GitHub repo settings + DeepSeek PR agent
│   └── <repo>/              # one dir per managed repo
│       └── workflows/       # workflow files pushed into the target repo
└── stripe/                  # one dir per Stripe account (one account per app), one state per concern
    └── workspaced/
        ├── tax/             # VAT rate
        └── webhooks/        # billing webhook → ai.workspaced.online
```

Each leaf directory has `versions.tf`, `providers.tf` and a `backend.tf` pointing at its own R2 key
(`homelab/<layer>/<path>.tfstate`); the resources sit beside them, split into files by concern.

## Usage

```bash
just deploy  <layer> <resource>          # terraform init + apply
just destroy <layer> <resource>          # terraform init + destroy
just output  <layer> <resource> <name>   # print a sensitive output
just list                                # print every deployable resource dir
```

Examples:

```bash
just deploy  cloudflare zones/pavel-usanli.online/internal
just deploy  proxmox    adguard-lxc
just deploy  github     kalpak44
just deploy  stripe     workspaced/webhooks
just destroy cloudflare zones/workspaced.online/email
just output  cloudflare tunnels/homelab tunnel_token
```

Via GitHub Actions: **Cloudflare**, **Proxmox**, **GitHub** and **Stripe** each have a **Deploy** and a **Destroy**
workflow - pick the resource from the dropdown, one dispatch per resource.

## Environment variables

All layers need R2 backend credentials:

| Var                     | Purpose                           |
|-------------------------|-----------------------------------|
| `AWS_ACCESS_KEY_ID`     | R2 access key                     |
| `AWS_SECRET_ACCESS_KEY` | R2 secret                         |
| `AWS_ENDPOINT_URL_S3`   | R2 S3-compat endpoint             |
| `R2_BUCKET_NAME`        | bucket that holds tfstate objects |

Cloudflare layer:

| Var                                      | Where used                                             |
|------------------------------------------|--------------------------------------------------------|
| `TF_VAR_cloudflare_api_token`            | every cloudflare/ dir                                  |
| `MJ_APIKEY_PUBLIC`, `MJ_APIKEY_PRIVATE`  | `zones/{pavel-usanli,workspaced}.online/email` (Mailjet provider) |

Proxmox layer:

| Var                                                 | Where used                      |
|-----------------------------------------------------|---------------------------------|
| `TF_VAR_proxmox_endpoint`, `_username`, `_password` | proxmox provider auth           |
| `TF_VAR_ssh_public_key`                             | injected via cloud-init         |
| `TF_VAR_ssh_private_key`                            | proxmox provider SSH connection |
| `TF_VAR_host_password`                              | root password baked into LXC/VM |

GitHub layer:

| Var                               | From env var              | Where used                                                              |
|-----------------------------------|---------------------------|-------------------------------------------------------------------------|
| `TF_VAR_github_token`             | `GH_ADMIN_TOKEN`          | github provider auth (Administration/Contents/Secrets/Workflows: write) |
| `TF_VAR_github_owner`             | `GH_OWNER`                | repo owner, defaults to `kalpak44`                                      |
| `TF_VAR_deepseek_api_key`         | `DEEPSEEK_APIKEY`         | published to the repo as the `DEEPSEEK_APIKEY` secret                   |
| `TF_VAR_sonar_token`              | `SONAR_TOKEN`             | published to repos with a Sonar gate                                    |
| `TF_VAR_android_keystore_base64`  | `ANDROID_KEYSTORE_BASE64` | `jacred-tv-client` only: the release signing keystore                   |

Stripe layer:

| Var                                | From env var                | Where used                                               |
|------------------------------------|-----------------------------|----------------------------------------------------------|
| `TF_VAR_stripe_api_key`            | `STRIPE_API_KEY`            | every `stripe/workspaced/` dir: that account's `terraform` key |

`TF_VAR_*` env vars are silently ignored by directories that don't declare the matching variable – this is why one
workflow can safely set them all. The Mailjet provider reads its keys from the environment directly, so it needs no `TF_VAR_`.
