# 8. Add services and verify the installation

Ansible stage: `05-services`.

Provision the standalone services needed by your selected applications. Backing
services must be ready before enabling dependent applications in Flux; other
services can be added after [Flux](<7 - Flux and workloads.md>). Run routine setup commands locally; the dedicated AI controller handles supported
autonomous maintenance migrations after initial setup.

## 1. Add standalone services

For each service, review its Terraform directory, inventory address and Ansible role.
Set any operator inputs still required locally and prepare its Vault record, then
provision and configure it. For example:

```bash
just --justfile terraform/Justfile deploy proxmox postgres-lxc
just --justfile ansible/Justfile configure postgres-lxc
just --justfile terraform/Justfile deploy proxmox redis-lxc
just --justfile ansible/Justfile configure redis-lxc
just --justfile terraform/Justfile deploy proxmox prometheus-lxc
just --justfile ansible/Justfile configure prometheus-lxc
just --justfile terraform/Justfile deploy proxmox grafana-lxc
just --justfile ansible/Justfile configure grafana-lxc
```

Use the [root service catalog](../README.md) for Portainer, RustFS, NocoBase and other
optional services. `just --justfile terraform/Justfile list` and
`just --justfile ansible/Justfile list` show the available resources.

## 2. Add application integrations when required

GitHub repository management, Stripe, Auth0, AWS, additional Cloudflare zones and
Packer images are independent integrations. Apply only those needed by your selected
applications, using [Terraform usage](../terraform/README.md) and the service catalog.
They are not prerequisites for the basic Proxmox, Vault and k3s environment.

Build or refresh the workspace VM image manually when needed:

```bash
just --justfile packer/Justfile build workspace-vm
```

This uses the local environment or Vault login to read the Hetzner token. There is
no scheduled or manually dispatched GitHub workflow for Packer builds.

## 3. Configure optional GitHub automation

The optional runner components are under `ansible/80-runner/01-vm/` through
`13-register/`. Each has its own `.env` and `just apply` command. Read each component’s README for its inputs and prerequisites. Start with
`01-vm`, then apply the guest components you need. Terraform and Ansible on the runner also support the dedicated autonomous maintenance
controller. Routine deploy/destroy workflows remain removed.

GitOps image updates, Vault-to-Actions credential synchronization and the two daily
maintenance agents run through GitHub Actions. See [Daily maintenance agents](<9 - Daily maintenance agents.md>) for schedules and setup. Set up the runner and their
specific credentials only if you need those workflows.

## 4. Optional Proxmox web-UI TLS

The three independent components under `ansible/81-proxmox-tls/` register the ACME
account, configure the Cloudflare DNS challenge, and issue the certificate. Edit each
component's `.env` and apply them in order:

```bash
just --justfile ansible/81-proxmox-tls/01-acme-account/Justfile apply --ask-pass
just --justfile ansible/81-proxmox-tls/02-acme-cloudflare/Justfile apply --ask-pass
just --justfile ansible/81-proxmox-tls/03-proxmox-certificate/Justfile apply --ask-pass
```

The Proxmox hostname must already resolve. Reapply `02-acme-cloudflare` after rotating
its API token. This configures the Proxmox web interface's certificate; guest service
certificates are managed by their individual roles.

## 5. Ongoing maintenance

`ansible/90-maintenance/` contains node-exporter installation and OS updates. Use
these after initial setup, with the same local service environment:

```bash
just --justfile ansible/Justfile configure node-exporter
just --justfile ansible/Justfile os-update
```

`os-update` patches the configured hosts and reboots those that need it. An optional
host argument limits the operation, for example `os-update vault`.

## 6. Verify the completed environment

Confirm all of the following before considering setup complete:

- Internal DNS resolves service hostnames to their intended LAN addresses.
- Vault health reports initialized and unsealed; the operator login works.
- Both k3s nodes report `Ready`.
- Flux kustomizations report ready, and enabled workloads have healthy pods.
- Persistent volumes bind and applications can retain data across a pod restart.
- External Secrets reads the intended Vault records.
- Internal and public HTTPS endpoints present valid certificates.
- Public applications are reachable through the Cloudflare tunnel.

Keep backups of Vault data and initialization material, application data and the
R2 Terraform state. Local bootstrap `.env` files are operator inputs and remain ignored
by Git; Vault integration for those files is still a future change.

Next: [Daily maintenance agents](<9 - Daily maintenance agents.md>).
