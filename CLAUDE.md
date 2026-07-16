# homelab-infra

Homelab infrastructure repository – a full-stack self-hosted environment built on Proxmox, managed with Terraform +
Ansible + Flux CD GitOps, with Cloudflare as the DNS and TLS authority.

---

## Overview

The repo has **three layers**, each with its own state model and lifecycle:

### 1. Terraform - infrastructure provisioning

Located in `terraform/`. Provisions Proxmox LXCs / VMs and Cloudflare records. **One state file per resource** on
Cloudflare R2 (S3-compatible backend). No monolithic root.

- `terraform/cloudflare/` - all Cloudflare records and email routing
    - `dns/private/<name>/` - LAN-only `*.internal` A records (unproxied)
    - `dns/public/<name>/` - internet-facing records (Cloudflare-proxied)
    - `shared/<name>/` - non-DNS Cloudflare (email routing)
- `terraform/proxmox/` - LXC containers and VMs on the Proxmox node
- `terraform/modules/{proxmox-lxc,proxmox-vm}/` - reusable primitives
- `terraform/Justfile` - `deploy <layer> <resource>`, `destroy <layer> <resource>`, `list`

### 2. Ansible - post-provisioning configuration

Located in `ansible/`. Structure mirrors `terraform/proxmox/` 1:1. Every service dir owns its playbook + colocated
`roles/`.

- `ansible/proxmox/<name>/playbook.yml` + `roles/<name>/`
- `ansible/proxmox/k3s-cluster/` has two playbooks (`cluster-setup.yml`, `flux-install.yml`)
- `ansible/inventories/hosts.yml` - single flat inventory
- `ansible/bootstrap/` - one-time fresh-Proxmox setup (Terraform user, base template artifacts, runner VM, TLS cert)
- `ansible/Justfile` - `configure <resource>`, `bootstrap <ip>`, `list`

### 3. GitOps on k3s (Flux CD)

Located in `gitops/` - reconciled automatically by Flux CD once the k3s cluster is up.

- Flux CD (bootstrapped by `ansible/proxmox/k3s-cluster/flux-install.yml`) watches this repo and applies manifests.
- Traefik ingress; cert-manager issues Let's Encrypt certs via Cloudflare DNS-01.
- External Secrets Operator syncs from Vault into k8s secrets.
- CrowdSec provides IDS/IPS + AppSec middleware.

See `gitops/README.md` for the in-cluster service list.

---

## Local Rules

@.claude/rules/dns-public.md
@.claude/rules/dns-private.md
@.claude/rules/workflows.md
@.claude/rules/commits.md

---

## Repository Layout

```
homelab-infra/
├── README.md                       # Setup + service catalog (source of truth for infra services)
├── CLAUDE.md                       # This file
├── terraform/
│   ├── README.md
│   ├── Justfile                    # just deploy | destroy | list
│   ├── cloudflare/
│   │   ├── dns/private/<name>/     # 14 dirs, one per LAN record set
│   │   ├── dns/public/<name>/      # 7 dirs, one per public record set
│   │   └── shared/<name>/          # non-DNS Cloudflare (email routing)
│   ├── proxmox/
│   │   └── <service>/              # 8 dirs (adguard-lxc, vault-lxc, ..., k3s-cluster)
│   └── modules/{proxmox-lxc,proxmox-vm}/
├── ansible/
│   ├── README.md
│   ├── ansible.cfg
│   ├── Justfile                    # just configure | bootstrap | bootstrap-pw | list
│   ├── inventories/hosts.yml
│   ├── bootstrap/                  # one-time fresh-Proxmox setup (4 phase playbooks)
│   └── proxmox/
│       └── <service>/              # mirrors terraform/proxmox/
│           ├── playbook.yml
│           └── roles/<role>/
├── gitops/
│   ├── README.md
│   └── clusters/homelab/
│       ├── flux-system/
│       ├── infrastructure/         # MetalLB, Traefik, cert-manager, NFS, External Secrets, CrowdSec
│       └── apps/{public,private}/
└── .github/workflows/
    ├── cloudflare-deploy.yml       # just deploy cloudflare <resource>
    ├── cloudflare-destroy.yml      # just destroy cloudflare <resource>
    ├── proxmox-deploy.yml          # just deploy proxmox <resource>
    ├── proxmox-destroy.yml         # just destroy proxmox <resource>
    └── ansible-configure.yml       # just configure <resource>
```

---

## Key Conventions

- **Per-resource Terraform state** – every leaf dir under `terraform/cloudflare/` and `terraform/proxmox/` has its own
  `backend.tf` with a unique R2 key. No cross-state refs; services reference shared Proxmox artifacts (VM 9000 template,
  LXC template file) by static string ID.
- **DNS records live under `terraform/cloudflare/dns/{private,public}/<name>/`** - not in a shared file.
- **Ansible dirs mirror Terraform dirs 1:1** – the Proxmox service that runs a workload has both a
  `terraform/proxmox/<name>/` and an `ansible/proxmox/<name>/` dir with the same name.
- **`just` is the single entry point** – CI workflows and local shells call the same `just <recipe>` commands.
- **TF_VAR_ / env-var flow** - workflows expose secrets as job-level env vars; `just` recipes and Terraform pick them
  up. Undeclared TF_VAR_/ansible extra vars are silently ignored, so one workflow can pass a union of vars safely.
- **Public apps** go in `gitops/clusters/homelab/apps/public/<name>/`; private apps in `.../apps/private/<name>/`.
- **TLS**: in-cluster via Traefik + cert-manager (DNS-01); standalone VMs/LXCs via certbot with Cloudflare DNS plugin (
  Ansible roles).
- **Secrets flow**: Vault → External Secrets Operator → Kubernetes Secret → app.
- **Self-hosted runner** lives at VM 101 on the Proxmox node.
- **VM 9000 (ubuntu-2404-template) and the Ubuntu LXC template are unmanaged by Terraform** - created manually or by
  `ansible/bootstrap/`. Deleting a proxmox/ state won't touch them.

## Adding or removing a service – what stays in sync

There is one dropdown entry, one dir, one description per resource. When adding **or** removing a service, update **all
** of these together:

| What                       | For                            | Which files                                                                                                                    |
|----------------------------|--------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| Terraform dir              | Provisioning                   | `terraform/cloudflare/<layer>/<name>/` or `terraform/proxmox/<name>/` (with `backend.tf` key `homelab/<layer>/<path>.tfstate`) |
| Ansible dir                | Config (Proxmox services only) | `ansible/proxmox/<name>/playbook.yml` + `roles/<name>/`                                                                        |
| Workflow dropdown          | CI                             | Choice list in the matching `.github/workflows/<layer>-{deploy,destroy}.yml` (and `ansible-configure.yml` when relevant)       |
| `just list` recipe         | Local UX                       | Description line in `terraform/Justfile` and/or `ansible/Justfile`                                                             |
| Root README services table | Source of truth                | `README.md`                                                                                                                    |
| Inventory                  | Ansible connection             | Host entry in `ansible/inventories/hosts.yml` (Proxmox services only)                                                          |
| GitOps README              | In-cluster only                | `gitops/README.md` (only for services deployed by Flux)                                                                        |

See `.claude/rules/workflows.md` for the workflow-specific checklist and
`.claude/rules/dns-{public,private}.md` for the DNS record patterns.