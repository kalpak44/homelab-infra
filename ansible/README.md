# Ansible

Run the numbered stages in dependency order. Provision hosts with Terraform first;
Ansible configures them afterward. The complete commands and verification steps are
in the [numbered build guide](<../docs/0 - Prerequisites.md#build-order>).

```
ansible/
├── 00-bootstrap/       # Proxmox Terraform access and base images
├── 01-networking/      # AdGuard DNS
├── 02-platform/        # NFS first, then k3s
├── 03-vault/           # Vault installation and operator-secret helpers
├── 04-gitops/          # Flux, after Vault and secret records are ready
├── 05-services/        # Databases, monitoring, tunnel connectors and other services
├── 80-runner/          # Optional GitHub runner; independent small components
├── 81-proxmox-tls/     # Optional Proxmox web-UI certificate components
├── 90-maintenance/     # OS updates and node exporter after initial setup
├── inventories/        # Shared host inventory
├── shared/             # Reused tasks, component launcher and connection handling
├── ansible.cfg
└── Justfile            # Stable service commands and secret helpers
```

Stages 00–05 describe the initial configuration order. The Vault container is provisioned
early with Terraform; its Ansible configuration runs in stage 03, after k3s because the
current Vault role also configures Kubernetes authentication. Within `02-platform`,
configure `nfs-vm` before `k3s-cluster`. Stages 80 and 81 are optional; 90 is maintenance.

## Commands and environment ownership

Bootstrap, runner and Proxmox TLS components each own their `.env`, `.env.example`,
Justfile, playbook and README. Apply one component from its directory:

```bash
cd ansible/00-bootstrap/01-terraform-access
# Edit this component's .env.
just apply
```

The shared launcher loads only that component's `.env`, and logs in with `SSH_PRIVATE_KEY`
(base64) from that file or your shell. Add `--ask-pass` only for a host without the key yet.

Every LXC and VM accepts only the operator key for root. `just ssh-access [host]` applies
that policy without running service roles; mihal-lxc keeps password login
(`ssh_password_login` in the inventory).

`just dns [host]` points the Proxmox node and every LXC/VM at `1.1.1.1` and `1.0.0.1`.
8.8.8.8 hands out Cloudflare edge addresses that time out from this network.

Existing service commands remain stable and use the root `.env`. From the repository root:

```bash
just --justfile ansible/Justfile configure adguard-lxc
just --justfile ansible/Justfile configure nfs-vm
just --justfile ansible/Justfile configure k3s-cluster
just --justfile ansible/Justfile configure vault-lxc
just --justfile ansible/Justfile configure k3s-cluster/flux
just --justfile ansible/Justfile list
```

A service folder keeps its playbook and colocated `roles/`. Its leaf name still matches
`terraform/proxmox/<name>/`; the numbered parent records when to configure it.
`Justfile` explicitly maps resource names to playbooks, so unknown names fail immediately.

## Keeping the structure maintainable

- Put a new service in the stage whose prerequisites it needs; retain its Terraform resource name.
- Keep role defaults, tasks, templates and handlers beside that service's playbook.
- Put reusable tasks in `shared/tasks/`; import them from the playbook directory explicitly.
- Update the command mapping, inventory, root catalog and the numbered build guide together.
- Keep setup order in `docs/`; component READMEs document only local inputs and behavior.
- Keep `.env` files ignored and `.env.example` files free of credentials.
- Run routine provisioning locally. The dedicated AI maintenance controller may apply
  validated autonomous migrations, using private Vault credentials and recovery checkpoints.
