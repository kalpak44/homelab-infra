# homelab-infra

Homelab infrastructure repository – a full-stack self-hosted environment built on Proxmox, managed with Terraform +
Ansible + Flux CD GitOps, with Cloudflare as the DNS and TLS authority.

---

## Overview

The repo has **three layers**, each with its own state model and lifecycle:

### 1. Terraform - infrastructure provisioning

Located in `terraform/`. Provisions Proxmox LXCs / VMs, Cloudflare, GitHub repo settings and Stripe. **One state
file per resource** on Cloudflare R2 (S3-compatible backend). No monolithic root.

- `terraform/cloudflare/` - everything on the Cloudflare side, grouped by what it is attached to
    - `tunnels/<name>/` - one tunnel each: its ingress, the public records pointing at it, WARP routes
    - `zones/<zone>/<concern>/` - per-zone state: `internal/` (`*.internal` A records), `email/`, `edge/` (WAF,
      redirects, zone settings)
- `terraform/proxmox/` - LXC containers and VMs on the Proxmox node
- `terraform/github/<repo>/` - GitHub repo settings + DeepSeek PR agent, one dir per managed repo
- `terraform/stripe/<account>/<concern>/` - one Stripe account per app, one state per concern (`tax/`, `webhooks/`)
- `terraform/modules/{proxmox-lxc,proxmox-vm}/` - reusable primitives
- `terraform/Justfile` - `deploy <layer> <resource>`, `destroy <layer> <resource>`, `list`

### 2. Ansible - post-provisioning configuration

Located in `ansible/`, grouped by execution stage: `00-bootstrap`, `01-networking`,
`02-platform`, `03-vault`, `04-gitops`, and `05-services`. Optional runner and Proxmox
TLS components live in `80-runner` and `81-proxmox-tls`; ongoing work lives in `90-maintenance`.

- Each service owns its playbook and colocated `roles/`; its leaf name matches Terraform.
- Bootstrap, runner and Proxmox TLS components own `.env`, `.env.example`, and `Justfile`.
- `shared/tasks/` holds reusable tasks; `inventories/hosts.yml` holds host addresses.
- Run component `just apply` locally or stable `just configure <resource>` service commands.
- Keep the setup sequence and next steps in numbered `docs/` guides, not duplicate stage READMEs.

### 3. GitOps on k3s (Flux CD)

Located in `gitops/` - reconciled automatically by Flux CD once the k3s cluster is up.

- Flux CD (bootstrapped by `ansible/04-gitops/flux/playbook.yml`) watches this repo and applies manifests.
- Traefik ingress; cert-manager issues Let's Encrypt certs via Cloudflare DNS-01.
- External Secrets Operator syncs from Vault into k8s secrets.
- CrowdSec provides IDS/IPS + AppSec middleware.

See `gitops/README.md` for the in-cluster service list.

---

## Local Rules

@.Codex/rules/dns-public.md
@.Codex/rules/dns-private.md
@.Codex/rules/github-repos.md
@.Codex/rules/workflows.md
@.Codex/rules/commits.md
@.Codex/rules/comments.md

---

## Repository Layout

```
homelab-infra/
├── README.md                       # Overview, commands and guide links
├── AGENTS.md                       # This file
├── LICENSE                         # MIT
├── SECURITY.md                     # Vulnerability reporting + scope
├── terraform/
│   ├── README.md
│   ├── Justfile                    # just deploy | destroy | list
│   ├── cloudflare/
│   │   ├── tunnels/<name>/         # homelab (k3s, every public hostname), mihal (WARP-only SSH)
│   │   └── zones/<zone>/<concern>/ # internal, email, edge; blocked-ips.txt shared by every edge/
│   ├── proxmox/
│   │   └── <service>/              # 10 dirs (adguard-lxc, vault-lxc, ..., k3s-cluster)
│   ├── github/
│   │   └── <repo>/                 # repo settings + DeepSeek maintenance agent (workflow + agent-prompts/)
│   ├── stripe/<account>/<concern>/ # one Stripe account per app; tax, webhooks
│   └── modules/{proxmox-lxc,proxmox-vm}/
├── ansible/
│   ├── 00-bootstrap/              # Proxmox access and base images
│   ├── 01-networking/             # DNS
│   ├── 02-platform/               # NFS and k3s
│   ├── 03-vault/                  # Vault and secret helpers
│   ├── 04-gitops/                 # Flux bootstrap
│   ├── 05-services/               # Remaining standalone services
│   ├── 80-runner/                 # Optional GitHub runner components
│   ├── 81-proxmox-tls/            # Optional web-UI TLS components
│   ├── 90-maintenance/            # Updates and node exporter
│   ├── shared/                    # Common tasks and component launcher
│   ├── inventories/hosts.yml
│   └── Justfile                   # Stable configure and secret-helper commands
├── gitops/
│   ├── README.md
│   ├── Justfile                    # just bump-images | list
│   └── clusters/homelab/
│       ├── flux-system/
│       ├── infrastructure/         # MetalLB, Traefik, cert-manager, NFS, External Secrets, CrowdSec
│       └── apps/{public,private}/
└── .github/workflows/
    ├── ai-update-agent.yml         # daily 06:00 UTC; source pins and health
    ├── ai-security-agent.yml       # daily 22:00 UTC; CrowdSec traffic/rules
    ├── secrets-sync.yml            # restore Actions credentials from Vault
    └── gitops-bump-images.yml      # just bump-images (daily cron 07:00 UTC)
```

---

## Key Conventions

- **Per-resource Terraform state** – every leaf dir under `terraform/cloudflare/`, `terraform/proxmox/` and
  `terraform/github/` has its own
  `backend.tf` with a unique R2 key. No cross-state refs; services reference shared Proxmox artifacts (VM 9000 template,
  LXC template file) by static string ID.
- **DNS records live under `terraform/cloudflare/dns/{private,public}/<name>/`** - not in a shared file.
- **Ansible service names match Terraform** – use `terraform/proxmox/<name>/` and
  `ansible/<stage>/<name>/`; choose the numbered stage by configuration prerequisites.
- **`just` is the single entry point** – routine provisioning stays local. The dedicated Codex maintenance agents may execute
  validated, checkpointed migrations automatically with Vault-backed credentials.
- **TF_VAR_ / env-var flow** - local recipes load the root `.env` or exported shell variables.
  Undeclared TF_VAR_/ansible extra vars are silently ignored.
- **Public apps** go in `gitops/clusters/homelab/apps/public/<name>/`; private apps in `.../apps/private/<name>/`.
- **TLS**: in-cluster via Traefik + cert-manager (DNS-01); standalone VMs/LXCs via certbot with Cloudflare DNS plugin (
  Ansible roles).
- **Secrets flow**: Vault → External Secrets Operator → Kubernetes Secret → app.
- **Self-hosted runner** lives at VM 101 on the Proxmox node.
- **VM 9000 (ubuntu-2404-template) and the Ubuntu LXC template are unmanaged by Terraform** - created manually or by
  `ansible/00-bootstrap/`. Deleting a proxmox/ state won't touch them.

## Adding or removing a service – what stays in sync

There is one dir and one description per resource. When adding **or** removing a service, update **all
** of these together:

| What                       | For                            | Which files                                                                                                                    |
|----------------------------|--------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| Terraform dir              | Provisioning                   | `terraform/cloudflare/{tunnels,zones}/...` or `terraform/proxmox/<name>/` (with `backend.tf` key `homelab/<layer>/<path>.tfstate`) |
| Ansible dir                | Config (Proxmox services only) | `ansible/<stage>/<name>/playbook.yml` + `roles/<name>/`                                                                        |
| `just list` recipe         | Local UX                       | Description line in `terraform/Justfile` and/or `ansible/Justfile`                                                             |
| Service catalog | Source of truth                | `docs/10 - Service catalog.md`                                                                                                                    |
| Inventory                  | Ansible connection             | Host entry in `ansible/inventories/hosts.yml` (Proxmox services only)                                                          |
| GitOps README              | In-cluster only                | `gitops/README.md` (only for services deployed by Flux)                                                                        |

See `.Codex/rules/workflows.md` for the workflow-specific checklist,
`.Codex/rules/dns-{public,private}.md` for the DNS record patterns, and
`.Codex/rules/github-repos.md` for managing a GitHub repo + its DeepSeek PR agent.