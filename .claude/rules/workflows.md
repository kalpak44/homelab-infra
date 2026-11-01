# Rules – GitHub Actions Workflows

All CI/CDs live in `.github/workflows/`. Eleven workflows, all running on the **self-hosted** runner (VM 101 on the
Proxmox node). All are `workflow_dispatch` (manual) except the four on a `schedule`: `gitops-bump-images.yml` daily,
`scanners-bump-pins.yml` weekly, and `ai-security-agent.yml` and `ai-update-agent.yml` nightly.

| File                     | Purpose                                    | Underlying command                   |
|--------------------------|--------------------------------------------|--------------------------------------|
| `cloudflare-deploy.yml`  | Terraform apply on a Cloudflare resource   | `just deploy cloudflare <resource>`  |
| `cloudflare-destroy.yml` | Terraform destroy on a Cloudflare resource | `just destroy cloudflare <resource>` |
| `proxmox-deploy.yml`     | Terraform apply on a Proxmox LXC/VM        | `just deploy proxmox <resource>`     |
| `proxmox-destroy.yml`    | Terraform destroy on a Proxmox LXC/VM      | `just destroy proxmox <resource>`    |
| `github-deploy.yml`      | Terraform apply on a managed GitHub repo   | `just deploy github <repo>`          |
| `github-destroy.yml`     | Terraform destroy on a managed GitHub repo | `just destroy github <repo>`         |
| `ansible-configure.yml`  | Ansible playbook against a configured host | `just configure <resource>`          |
| `gitops-bump-images.yml` | Point tracked apps at the newest published image | `just bump-images` (in `gitops/`) |
| `scanners-bump-pins.yml` | Point the syft/grype pins at the newest release | `just bump-scanners`            |
| `ai-security-agent.yml`  | Review a day of requests, ban sources, tune CrowdSec | the agent prompt, not a recipe |
| `ai-update-agent.yml`    | Update third-party software and patch every host | the agent prompt, plus `just os-update` |

Every workflow has one job with three steps: `checkout`, `extractions/setup-just@v2`, and a single `just <recipe>` call.
All actual logic lives in the layer's `Justfile`.

`ai-security-agent.yml` is the one exception, and it is the only workflow here that writes to this repository on its
own. It runs Codex against DeepSeek nightly at 22:00 UTC — 00:00 in Sofia on EET and 01:00 on EEST, chosen late so the
day under review is always over. Its policy lives in `.github/agent-prompts/ai-security-agent.md`, which is the one
place to change what it will and will not do; the workflow only assembles tools and credentials. It reads the cluster
through a token minted for the `security-agent` ServiceAccount
(`gitops/clusters/homelab/infrastructure/crowdsec/agent-rbac.yaml`), so the read-only boundary is the API
server's rather than the prompt's — never hand it an admin kubeconfig to save a step. Its two edit points are
`gitops/clusters/homelab/infrastructure/crowdsec/blocked-ips.txt` and `terraform/cloudflare/shared/zero-trust/blocked-ips.txt`
— plain lists, so a night's bans never grow the HelmRelease or the HCL. Both are read by rules that already exist,
because each zone allows one WAF ruleset and a second one would delete the first's rules on every apply. The CrowdSec
list is a ConfigMap mount, which a running pod does not reload, so the `blocked-ips-sha256` pod annotation in
`helmrelease.yaml` has to move with it or the DaemonSet silently keeps the old list.

`ai-update-agent.yml` is the other. It runs at 06:00 UTC and keeps third-party software current across all three
layers: the chart and image pins in `gitops/`, the version variables in the Ansible role defaults, and the OS packages
on every LXC and VM. Its policy is `.github/agent-prompts/ai-update-agent.md`, and it reads the cluster through the
`update-agent` ServiceAccount in the same `agent-rbac.yaml` — the read-only ClusterRole is shared by both agents.

It also owns three things beyond version numbers. It **checks and repairs before it
updates** — pods, reconciliation, failed units, disk headroom on the shared thin pool, and
snapshots a previous run left behind — because a fault inherited at the start gets blamed
on the bump and reverting does not clear it. It **keeps TLS valid**: certbot renewal is
tested with `--dry-run` rather than trusted, since `certbot.timer` reports success whether
or not the renewal worked — `rabbitmq.internal` was found expired for two months behind a
healthy timer, because a rotated Cloudflare token had been left stale in
`/etc/letsencrypt/cloudflare.ini`. And it **maintains its own prompt**, which is the one
file under `.github/` it may edit: every table in it is a snapshot of a homelab that
changes, and a stale entry reads as authoritative, so the next run acts on it.

**Majors are in scope and so are their migrations, which is why the snapshot is not optional.** `local-lvm` is
LVM-thin, so every guest snapshots; the agent takes one over SSH to the Proxmox node with `pct`/`qm` before any major
and rolls back to it on failure. A stateful bump cannot be undone by reverting the commit — CrowdSec proved that on
2026-11-01, when its schema migration left the older binary unable to start at all — so for anything holding state the
snapshot *is* the rollback. One major per run, and the snapshot is deleted once the upgrade verifies, because two
snapshots on one guest grow the thin pool until the node wedges.

The OS half is `just os-update`, which runs `ansible/maintenance/os-update.yml`. **That playbook's play order is the
safety mechanism, not a style choice**: application hosts, then storage, then the k3s worker, then the server, then
the tunnel, then AdGuard last, one host at a time, each gated on the previous coming back. AdGuard is last because it
is the LAN resolver and nothing — the runner included — resolves anything while it reboots. The runner VM and the
Proxmox node are patched but never rebooted, because the job runs on one and inside the other, so a reboot would kill
the process doing the patching and leave nothing to verify or roll back. Never reorder, parallelise, or `--limit` the
playbook to work around a stubborn host.

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

| Workflow                      | Env vars                                                                                                                                                                                                                                                                                              |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `cloudflare-{deploy,destroy}` | `AWS_*` (R2 creds), `R2_BUCKET_NAME`, `TF_VAR_cloudflare_api_token`                                                                                                                                                                                                                                  |
| `proxmox-{deploy,destroy}`    | `AWS_*` (R2 creds), `R2_BUCKET_NAME`, `TF_VAR_proxmox_{endpoint,username,password}`, `TF_VAR_ssh_{public,private}_key`, `TF_VAR_host_password`                                                                                                                                                       |
| `github-{deploy,destroy}`     | `AWS_*` (R2 creds), `R2_BUCKET_NAME`, `GH_ADMIN_TOKEN`, `GH_OWNER`, `DEEPSEEK_APIKEY`, `SONAR_TOKEN`, `ANDROID_KEYSTORE_BASE64` (secret names can't start with `GITHUB_`)                                                                                           |
| `ansible-configure`           | `HOST_PASSWORD` (root SSH + become for every host) + service creds (`CLOUDFLARE_API_TOKEN`, `LETSENCRYPT_EMAIL`, `ADGUARD_*`, `VAULT_*`, `POSTGRESQL_*`, `PGADMIN_*`, `REDIS_*`, `RABBITMQ_*`, `FLUX_GITHUB_TOKEN`, `CLOUDFLARE_TUNNEL_TOKEN`) — Ansible reads them in the Justfile's `configure` recipe via `-e "<name>=$VAR"` |

## Choice dropdowns

Every workflow's `options:` lists the deployable resource paths for that layer:

- `cloudflare-*.yml`: 15 entries (13 private DNS + 2 shared). Public DNS records are managed inside `shared/zero-trust` — no individual `dns/public/` entries.
- `proxmox-*.yml`: 10 entries (`adguard-lxc`, `vault-lxc`, `postgres-lxc`, `redis-lxc`, `rabbitmq-lxc`,
  `cloudflared-lxc`, `nocobase-lxc`, `nfs-vm`, `portainer-vm`, `k3s-cluster`).
- `ansible-configure.yml`: 11 entries (the 10 proxmox services + `k3s-cluster/flux`, which maps to `flux-install.yml` in
  the Justfile).
- `github-*.yml`: one entry per dir under `terraform/github/` (see `github-repos.md`).

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

**Public service** (internet-facing, through the tunnel):
1. Add one entry to `local.public_k3s_apps` in `terraform/cloudflare/shared/zero-trust/main.tf` (see `dns-public.md`).
2. Deploy: `just deploy cloudflare shared/zero-trust` (or **Cloudflare - Deploy** → `shared/zero-trust`).
3. Manifests: `gitops/clusters/homelab/apps/public/<name>/`.
4. `gitops/README.md` and `README.md` updated.

**Private service** (LAN-only):
1. DNS record dir: `terraform/cloudflare/dns/private/<name>/` (see `dns-private.md`).
2. Add `dns/private/<name>` to `cloudflare-{deploy,destroy}.yml` dropdowns and to `terraform/Justfile`'s `list`.
3. Manifests: `gitops/clusters/homelab/apps/private/<name>/`.
4. `gitops/README.md` and `README.md` updated.

No workflow entry is needed for the in-cluster manifests themselves — Flux reconciles from Git.

## Checklist – removing a service

Reverse: run `<layer>-destroy.yml` (or `just destroy`) which removes the actual resource, then delete every dir,
dropdown entry, list line, README row, and inventory entry above.
