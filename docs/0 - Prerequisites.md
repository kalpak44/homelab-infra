# 0. Prerequisites

Follow this guide from an existing Proxmox host to a working homelab. Commands run
on the operator computer. Run command blocks from the repository root unless a
step explicitly says otherwise.

## Prerequisites

### Proxmox

Start with an existing Proxmox VE host or cluster where the homelab's virtual
machines and LXC containers will run. Installing Proxmox itself is a prerequisite
to using this repository.

You need administrative access to Proxmox and SSH access to the target node.
The current configuration deploys to a single node named `proxmox`, even if that
node belongs to a larger Proxmox cluster.

The Proxmox environment is separate from the k3s cluster: the setup provisions
the k3s virtual machines inside Proxmox later.

## Local tools and accounts

Install `just`, Terraform and Ansible on the operator computer. Use an Ansible
installation that includes the collections used by the repository; its NFS role
uses `community.general` and `ansible.posix`. The AdGuard and mihal roles hash passwords,
which requires Python `passlib` in the Python environment running Ansible.

You also need:

- Root/admin SSH access to Proxmox and an operator SSH key pair.
- A Cloudflare account, DNS API token and R2 bucket for Terraform state.
- A GitHub repository and Flux bootstrap token when you reach step 7.
- Unused LAN addresses matching the Terraform definitions and Ansible inventory.

Check the current addresses in `ansible/inventories/hosts.yml` and resource definitions
before applying. Commands in this guide run locally. Bootstrap components each read
their own `.env`; current Terraform and service recipes read the ignored root `.env`.

## Environment files

For components in `00-bootstrap`, `80-runner` and `81-proxmox-tls`, copy that
component's `.env.example` to `.env` if it is missing, then edit it. Local `.env`
files are ignored by Git, so a fresh clone does not contain them. Set their mode
to `600`. Each dedicated `just apply` reads only that component's environment.

Terraform and the current service recipes use the ignored root `.env`. Initialize
it from the root `.env.example` if missing, preserving existing values. Vault
becomes available in step 6; until then, these local inputs establish initial access.

## Cloudflare token permissions

The single `CLOUDFLARE_API_TOKEN` needs:

| Type    | Resource                | Permission  |
|---------|-------------------------|-------------|
| Zone    | DNS                     | Edit        |
| Account | Cloudflare Tunnel       | Edit        |
| Account | Zero Trust              | Edit        |
| Account | Email Routing Addresses | Edit + Read |
| Zone    | Email Routing Rules     | Edit + Read |
| Zone    | Zone Settings           | Edit + Read |
| Zone    | SSL and Certificates    | Edit        |

Zone resource is scoped to your domain (e.g. `pavel-usanli.online`). Account-level permissions cover the Zero Trust
tunnel (`cloudflare/tunnels/homelab`). **SSL and Certificates** is what the Cloudflare-for-SaaS custom hostnames in
`saas.tf` need; without it every call to that API returns a bare `Authentication error` rather than a permission
message, so a token missing it looks like a broken token.


## Build order

Follow the guides in numerical order. Each explains what to apply, the inputs needed,
and the checks to complete before continuing.

| Step | Guide | Ansible stage | Result |
|------|-------|---------------|--------|
| 0 | Prerequisites | — | Proxmox access, local tooling and provider accounts |
| 1 | [Bootstrap](<1 - Bootstrap.md>) | `00-bootstrap` | Terraform role, user, permissions and API token |
| 2 | [LXC template](<2 - LXC template.md>) | `00-bootstrap` | Downloaded and SSH-ready Ubuntu archive |
| 3 | [Vault container](<3 - Vault container.md>) | Terraform only | LXC 201 provisioned; Vault installation follows in step 6 |
| 4 | [Networking](<4 - Networking.md>) | `01-networking` | Internal DNS, AdGuard, host resolvers and optional tunnel connector |
| 5 | [Storage and k3s](<5 - Storage and k3s.md>) | `00-bootstrap`, `02-platform` | VM template, NFS and two ready cluster nodes |
| 6 | [Vault secrets](<6 - Vault secrets.md>) | `03-vault` | Initialized Vault, operator access and secret records |
| 7 | [Flux and workloads](<7 - Flux and workloads.md>) | `04-gitops` | GitOps infrastructure and application reconciliation |
| 8 | [Services and verification](<8 - Services and verification.md>) | `05-services` | Additional services and final checks |
| 9 | [Daily maintenance agents](<9 - Daily maintenance agents.md>) | Self-hosted runner | Daily update checks and traffic-based CrowdSec improvements |

Optional runner setup lives in `80-runner`, Proxmox web-UI TLS in `81-proxmox-tls`,
and ongoing updates in `90-maintenance`. These are not required for initial Terraform access.

Next: [Bootstrap](<1 - Bootstrap.md>).

Reference: [Service catalog](<10 - Service catalog.md>) · [Managed repositories](<11 - Managed repositories.md>).
