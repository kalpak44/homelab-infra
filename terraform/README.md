# Terraform

Provisions all long-lived infrastructure.

## Layout

```
terraform/
├── Justfile                 # deploy / destroy / output / list recipes
├── aws/                     # AWS accounts, SSO config and backend credential helper
│   ├── personal/account/    # read-only identity check for 039959484327
│   ├── personal/budgets/    # USD 20 monthly actual-cost email alert
│   └── personal/admin/      # SSO-only: scoped Terraform IAM user, its policy and key
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
├── stripe/                  # one dir per Stripe account (one account per app), one state per concern
│   └── workspaced/
│       ├── tax/             # VAT rate
│       └── webhooks/        # billing webhook → ai.workspaced.online
└── auth0/                   # one dir per Auth0 tenant (one tenant per app)
    └── workspaced/          # sign-in for ai.workspaced.online
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
just deploy  auth0      workspaced
just plan-aws personal/account
just deploy  aws        personal/account
just deploy-aws-admin   personal          # SSO sign-in; manages the Terraform user
just destroy cloudflare zones/workspaced.online/email
just output  cloudflare tunnels/homelab tunnel_token
```

Run routine commands locally from `terraform/`. The dedicated AI maintenance controller
may also apply a validated saved plan for an autonomous migration; deploy/destroy workflows remain removed.
`just bump-scanners` also runs locally; it applies managed GitHub repositories after updating their pins.

## Environment variables

Local recipes load the root `.env` automatically. Exported shell variables take precedence over `.env`.

All layers need R2 backend credentials:

The AWS layer uses separate local SSO credentials for the AWS provider. See
[AWS setup](aws/README.md) for its environment variables and authentication commands.

| Var                     | Purpose                           |
|-------------------------|-----------------------------------|
| `R2_ACCESS_KEY_ID`     | R2 access key                     |
| `R2_SECRET_ACCESS_KEY` | R2 secret                         |
| `R2_ENDPOINT`         | R2 S3-compat endpoint             |
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

Both come from `SSH_PRIVATE_KEY` (base64): the Justfile decodes it and derives the public
half. Guests get no password, so root logs in with that key only.

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

AWS layer: `AWS_TERRAFORM_ACCESS_KEY_ID` and `AWS_TERRAFORM_SECRET_ACCESS_KEY`, the scoped
Terraform user's key, mapped to the provider by `aws/terraform.sh`. The `admin` concern uses
the `aws-admin` SSO session instead; see [`aws/README.md`](aws/README.md).

Auth0 layer: the provider reads `AUTH0_CLIENT_ID` and `AUTH0_CLIENT_SECRET` itself, and `MJ_APIKEY_PUBLIC` /
`MJ_APIKEY_PRIVATE` map to `TF_VAR_mailjet_api_key_{public,private}` for its SMTP mail.

`TF_VAR_*` env vars are silently ignored by directories that don't declare the matching variable – this is why one
local recipe can safely set them all. The Mailjet provider reads its keys from the environment directly, so it needs no `TF_VAR_`.
