# Rules – GitHub Actions workflows

These workflows run on the self-hosted runner:

| File | Trigger | Command |
|------|---------|---------|
| `gitops-bump-images.yml` | Daily 07:00 UTC and manual dispatch | `just bump-images <app> <sha>` in `gitops/` |
| `secrets-sync.yml` | Manual dispatch on main | `just secrets-sync` in `ansible/` |
| `ai-update-agent.yml` | Daily 06:00 UTC + manual | Read-only evidence collection and validated source-pin proposals |
| `ai-security-agent.yml` | Daily 22:00 UTC + manual | Traffic-based CrowdSec defense/version proposals |

Terraform and Ansible execution is local only, including playbooks, OS upgrades, host restarts and provisioning. Agents may commit source pins and GitOps defenses; they do not apply Terraform or Ansible.
Do not add infrastructure deploy/destroy workflows or workflow resource dropdowns.
The secret-sync recipe executes the Python Vault helper, not an Ansible playbook.
Its location is `ansible/03-vault/operator-secrets/secrets.py`.

## Manual infrastructure operations

Use the layer's Justfile locally. Bootstrap, runner and Proxmox TLS components have
dedicated Justfiles and local environments. Follow the numbered guides in `docs/`
and the folder map in `ansible/README.md` for their sequence and prerequisites.

Packer images are also built manually:

```bash
just --justfile packer/Justfile build workspace-vm
```

The local Packer recipe reads the Hetzner token from the environment or Vault,
builds a snapshot and retains the configured number of recent images.

## Keeping services in sync

When adding or removing a service, update its Terraform resource, Ansible stage
and command mapping, inventory, `just list` output and service catalog together.
No infrastructure workflow entry is needed. Flux continues reconciling Kubernetes
manifests from Git, and source repositories can still dispatch GitOps image updates.

## Agent publication boundary

The shared composite action invokes `.github/scripts/infra_agent.py`. Model runs use
a read-only checkout and a restricted environment. The controller validates file and
field allowlists, upstream versions and CrowdSec wiring before publishing; Flux applies
GitOps changes. Source pins for standalone hosts require a local operator command.

There is no numerical ban cap. Each source requires behavioral evidence; trusted and
Cloudflare proxy addresses are protected. Prompts treat traffic and upstream text as
untrusted data. See `docs/9 - Daily maintenance agents.md` for setup and credential cleanup.
