# Rules – GitHub Actions Workflows

All CI/CDs live in `.github/workflows/`. Five workflows, all `workflow_dispatch` (manual), all running on the *
*self-hosted** runner (VM 101 on the Proxmox node):

| File                     | Purpose                                    | Underlying command                   |
|--------------------------|--------------------------------------------|--------------------------------------|
| `cloudflare-deploy.yml`  | Terraform apply on a Cloudflare resource   | `just deploy cloudflare <resource>`  |
| `cloudflare-destroy.yml` | Terraform destroy on a Cloudflare resource | `just destroy cloudflare <resource>` |
| `proxmox-deploy.yml`     | Terraform apply on a Proxmox LXC/VM        | `just deploy proxmox <resource>`     |
| `proxmox-destroy.yml`    | Terraform destroy on a Proxmox LXC/VM      | `just destroy proxmox <resource>`    |
| `ansible-configure.yml`  | Ansible playbook against a configured host | `just configure <resource>`          |

Every workflow has one job with three steps: `checkout`, `extractions/setup-just@v2`, and a single `just <recipe>` call.
All actual logic lives in the layer's `Justfile`.

## Shape of every workflow

```yaml
on:
  workflow_dispatch:
    inputs:
      resource:
        description: ...
        required: true
        type: choice
        options:
          - <one entry per deployable dir>

jobs:
  <name>:
    runs-on: self-hosted
    defaults:
      run:
        working-directory: <terraform|ansible>
    env:
      # secrets injected as env vars — Terraform reads TF_VAR_*, Ansible reads them via `-e` in the recipe
      ...
    steps:
      - uses: actions/checkout@v4
      - uses: extractions/setup-just@v2
      - run: just <recipe> "${{ inputs.resource }}"
```

## Environment variables

Terraform workflows use **`TF_VAR_`** prefixed env vars so undeclared vars are silently ignored per dir (unlike `-var`
flags which error):

| Workflow                      | Env vars                                                                                                                                                                                                                                                                               |
|-------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `cloudflare-{deploy,destroy}` | `AWS_*` (R2 creds), `R2_BUCKET_NAME`, `TF_VAR_cloudflare_api_token`, `TF_VAR_haproxy_public_ip`                                                                                                                                                                                        |
| `proxmox-{deploy,destroy}`    | `AWS_*` (R2 creds), `R2_BUCKET_NAME`, `TF_VAR_proxmox_{endpoint,username,password}`, `TF_VAR_ssh_{public,private}_key`                                                                                                                                                                 |
| `ansible-configure`           | `SSH_PRIVATE_KEY` + service creds (`CLOUDFLARE_API_TOKEN`, `LETSENCRYPT_EMAIL`, `ADGUARD_*`, `VAULT_*`, `POSTGRESQL_*`, `PGADMIN_*`, `REDIS_*`, `RABBITMQ_*`, `HAPROXY_STATS_*`, `FLUX_GITHUB_TOKEN`) — Ansible reads them in the Justfile's `configure` recipe via `-e "<name>=$VAR"` |

## Choice dropdowns

Every workflow's `options:` lists the deployable resource paths for that layer:

- `cloudflare-*.yml`: 22 entries (14 private DNS + 7 public DNS + 1 shared).
- `proxmox-*.yml`: 9 entries (`adguard-lxc`, `vault-lxc`, `postgres-lxc`, `redis-lxc`, `rabbitmq-lxc`, `haproxy-lxc`,
  `nfs-vm`, `portainer-vm`, `k3s-cluster`).
- `ansible-configure.yml`: 10 entries (the 9 proxmox services + `k3s-cluster/flux`, which maps to `flux-install.yml` in
  the Justfile).

Adding or removing a resource means updating the dropdown in **every** relevant workflow **and** the matching `list`
recipe in `terraform/Justfile` / `ansible/Justfile`.

## Bootstrap (not wired to CI)

`ansible/bootstrap/` handles the one-time setup of a fresh Proxmox node (Terraform user + token, base template
artifacts, runner VM, TLS cert). Run locally via `just bootstrap <proxmox-ip>` (or `just bootstrap-pw <ip>` for a node
without SSH keys yet) from the `ansible/` dir.

## Checklist – adding a new Proxmox service (LXC or VM)

1. **`terraform/proxmox/<name>/`** - copy an existing service dir; edit `main.tf`, `variables.tf`, `backend.tf` (state
   key `homelab/proxmox/<name>.tfstate`).
2. **`ansible/proxmox/<name>/`** - copy a matching dir; edit `playbook.yml` and `roles/<role>/`.
3. **`ansible/inventories/hosts.yml`** - add the host under `lxc` or `vm` group.
4. **`.github/workflows/proxmox-deploy.yml`** + **`proxmox-destroy.yml`** - append `<name>` to the `options:` list.
5. **`.github/workflows/ansible-configure.yml`** - append `<name>` to the `options:` list.
6. **`terraform/Justfile`** `list` recipe + **`ansible/Justfile`** `list` recipe - add a description line.
7. **`README.md`** - add row to the services table.
8. If the service has an internal hostname, add its DNS record dir under `terraform/cloudflare/dns/private/<name>/` and
   wire into `cloudflare-{deploy,destroy}.yml` + `terraform/Justfile` list.

## Checklist – adding an in-cluster (Flux) service

In-cluster services are managed by Flux, not by Terraform/Ansible — the only piece that touches these workflows is the
DNS record.

1. Manifests: `gitops/clusters/homelab/apps/{public,private}/<name>/` (see `dns-public.md` / `dns-private.md`).
2. DNS record dir: `terraform/cloudflare/dns/{public,private}/<name>/`.
3. Add `dns/{public,private}/<name>` to `cloudflare-{deploy,destroy}.yml` dropdowns and to `terraform/Justfile`'s
   `list`.
4. `gitops/README.md` and `README.md` updated.

No workflow entry is needed for the in-cluster manifests themselves — Flux reconciles from Git.

## Checklist – removing a service

Reverse: run `<layer>-destroy.yml` (or `just destroy`) which removes the actual resource, then delete every dir,
dropdown entry, list line, README row, and inventory entry above.