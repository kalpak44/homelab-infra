# homelab-infra

Self-hosted infrastructure on Proxmox, provisioned with Terraform, configured with
Ansible, and reconciled on k3s by Flux. Terraform state lives in Cloudflare R2;
Vault holds service secrets; Cloudflare provides DNS and public ingress.

## Start here

- [Step-by-step build guide](<docs/0 - Prerequisites.md#build-order>) — prerequisites through working services.
- [Service catalog](<docs/10 - Service catalog.md>) — addresses, resource locations and service notes.
- [Daily maintenance agents](<docs/9 - Daily maintenance agents.md>) — update checks, traffic review and credentials.
- [Managed repositories](<docs/11 - Managed repositories.md>) — application CI and release agents.

## Repository map

| Directory | Purpose |
|-----------|---------|
| [`terraform/`](terraform/README.md) | Independent resources with separate R2 state |
| [`ansible/`](ansible/README.md) | Numbered configuration stages and local commands |
| [`gitops/`](gitops/README.md) | Flux-managed cluster infrastructure and workloads |
| `packer/` | Manually built VM images |
| `.github/` | Self-hosted workflows, agent prompts and validation scripts |
| `docs/` | Setup sequence and detailed references |

## Local operations

Run from the repository root after completing the relevant setup steps:

```bash
just --justfile terraform/Justfile list
just --justfile ansible/Justfile list
just --justfile terraform/Justfile deploy proxmox <resource>
just --justfile ansible/Justfile configure <resource>
```

Bootstrap components have their own `.env.example`, ignored `.env`, and `just apply`.
Current Terraform and service recipes load the ignored root `.env`. Routine infrastructure commands run locally. The dedicated daily AI controller may execute
validated migrations automatically with Vault-backed credentials and recovery checkpoints.

## Automation

All workflows run on the self-hosted runner. Scheduled jobs also support manual dispatch.

| Workflow | Schedule (UTC) |
|----------|----------------|
| AI Update Agent | Daily 06:00 |
| GitOps image bumps | Daily 07:00 |
| AI Security Agent | Daily 22:00 |
| Vault-to-Actions secret synchronization | Manual |

Agents publish validated source changes; Flux applies GitOps changes. The AI prioritizes security fixes and performs validated migrations, including major
upgrades with brief planned downtime. See the [agent guide](<docs/9 - Daily maintenance agents.md>) for boundaries and reports.

[Security policy](SECURITY.md) · [MIT license](LICENSE)
