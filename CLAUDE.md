# homelab-infra

Homelab infrastructure repository — a full-stack self-hosted environment built on Proxmox, managed with Terraform + Ansible + Flux CD GitOps, with Cloudflare as the DNS and TLS authority.

---

## Overview
The repo is split into **two distinct layers**:

### Part 1 — General Infrastructure (Terraform + Cloudflare DNS)

Located in `terraform/` and deployed via GitHub Actions (`deploy.yml`).

Provisions all underlying compute and DNS:

- **Proxmox** hypervisor hosts LXC containers and VMs declared as Terraform modules (`proxmox-lxc/`, `proxmox-vm/`).
- **Cloudflare DNS** records for every service are managed in `terraform/shared.tf`.
- **Terraform state** is stored remotely in Cloudflare R2 (S3-compatible backend).
- Ansible playbooks in `ansible/` run post-provisioning to configure each service.

→ See `README.md` for the current list of provisioned services and their IPs.

---

### Part 2 — GitOps on k3s (Flux CD + Cloudflare DNS)

Located in `gitops/` and reconciled automatically by Flux CD (polls GitHub every 1 minute).

Manages all workloads running inside the k3s cluster:

- **Flux CD** (bootstrapped by the `ansible/playbooks/flux.yml` playbook) watches this repo and applies manifests.
- **Traefik** is the ingress controller; it obtains TLS certificates via cert-manager using Cloudflare DNS-01 challenges.
- **External Secrets Operator** syncs secrets from Vault into Kubernetes.
- **CrowdSec** provides IDS/IPS and AppSec middleware on all public ingress routes.

→ See `gitops/README.md` for the current list of public and private in-cluster services.

---

## Local Rules — DNS Patterns

@.claude/rules/public-services.md
@.claude/rules/private-services.md

## Local Rules — GitHub Workflows

@.claude/rules/github-workflows.md

## Local Rules — Git

@.claude/rules/git.md

---

## Repository Layout

```
homelab-infra/
├── README.md            # Source of truth — all provisioned services + IPs
├── terraform/           # Part 1 — Proxmox VMs/LXCs + Cloudflare DNS records
│   ├── shared.tf        # All Cloudflare DNS records
│   ├── main.tf          # Module instantiations
│   ├── providers.tf     # Proxmox + Cloudflare provider config
│   ├── backend.tf       # Remote state on Cloudflare R2
│   └── modules/         # proxmox-lxc, proxmox-vm, adguard, vault, postgres …
├── ansible/             # Post-provisioning configuration
│   ├── inventories/     # Homelab host groups + vars
│   ├── playbooks/       # One playbook per service
│   └── roles/           # Role logic (install, configure, TLS, etc.)
├── gitops/              # Part 2 — Flux CD manifests
│   ├── README.md        # Source of truth — all in-cluster public + private services
│   └── clusters/homelab/
│       ├── flux-system/ # Flux core (auto-generated)
│       ├── infrastructure/  # MetalLB, Traefik, NFS provisioner, External Secrets, CrowdSec
│       └── apps/
│           ├── public/  # Internet-facing workloads
│           └── private/ # Internal-only workloads
├── .scripts/
│   ├── deploy.sh        # Local equivalent of deploy.yml — reads secrets from system env vars
│   └── destroy.sh       # Local equivalent of destroy.yml — reads secrets from system env vars
└── .github/workflows/
    ├── deploy.yml       # Terraform apply + Ansible (manual trigger, self-hosted runner)
    └── destroy.yml      # Terraform destroy (target module)
```

---

## Key Conventions

- All Terraform DNS records are in `terraform/shared.tf` — add new records there.
- Public apps go in `gitops/clusters/homelab/apps/public/<name>/`; private apps in `.../apps/private/<name>/`.
- TLS for in-cluster services is handled by Traefik + cert-manager (Cloudflare DNS-01). TLS for standalone VMs/LXCs is handled by certbot with the Cloudflare DNS plugin (via Ansible roles).
- Secrets flow: Vault → External Secrets Operator → Kubernetes Secret → app.
- The self-hosted GitHub Actions runner lives at VM 101 on the Proxmox node.

## Keep these four things in sync on every service change

When adding **or** removing any service, all of the following must be updated together — never update one without the others:

| What | Why |
|---|---|
| `README.md` | Source of truth for infrastructure-layer services (VMs/LXCs, IPs, DNS) |
| `gitops/README.md` | Source of truth for in-cluster services (public + private k3s workloads) |
| `.github/workflows/deploy.yml` + `destroy.yml` | CI/CD must know about the service |
| `.scripts/deploy.sh` + `destroy.sh` | Local scripts must mirror the workflows exactly |

See `.claude/rules/github-workflows.md` for the full per-service checklists.