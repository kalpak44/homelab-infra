# Rules — GitHub Actions Workflows

All CI/CD lives in `.github/workflows/`. There are exactly two workflows:

| File | Trigger | Purpose |
|---|---|---|
| `deploy.yml` | `workflow_dispatch` | Terraform apply + Ansible provisioning |
| `destroy.yml` | `workflow_dispatch` | Terraform destroy (targeted) |

Both run on the **self-hosted** runner (VM 101 on the Proxmox node).

---

## Shared job-level env vars

Both workflows set these at the job level (not step level):

```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}       # R2 backend auth
  AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
  AWS_ENDPOINT_URL_S3: ${{ secrets.R2_ENDPOINT }}
  TF_VAR_ssh_private_key: ${{ secrets.SSH_PRIVATE_KEY }}   # picked up by Terraform automatically
```

`deploy.yml` additionally sets:
```yaml
  TF_REFRESH_FLAG: ${{ inputs.refresh == false && '-refresh=false' || '' }}
```

---

## Service naming conventions

Services map directly to Terraform modules and Ansible playbooks by the same name:

| `service` input value | Terraform module | Ansible playbook |
|---|---|---|
| `adguard` | `module.adguard` | `playbooks/adguard.yml` |
| `vault` | `module.vault` | `playbooks/vault.yml` |
| `postgres` | `module.postgres` | `playbooks/postgres.yml` |
| `redis` | `module.redis` | `playbooks/redis.yml` |
| `portainer` | `module.portainer` | `playbooks/portainer.yml` |
| `haproxy` | `module.haproxy` | `playbooks/haproxy.yml` |
| `nfs` | `module.nfs` | `playbooks/nfs.yml` |
| `k3s` | `module.k3s` | `playbooks/k3s.yml` |
| `proxmox-dns` | `cloudflare_record.proxmox` | _(no Ansible step)_ |
| `k3s/flux` | _(no Terraform step)_ | `playbooks/flux.yml` |
| `k3s/flux/<name>` | `cloudflare_record.<name>` only | _(no Ansible step)_ |

### Special behaviour

- **`proxmox-dns`** — Terraform only (DNS record update). Ansible step is skipped via its `if` condition.
- **`k3s/flux`** — Ansible only (Flux bootstrap). Terraform init/apply steps are skipped via `if: inputs.service != 'k3s/flux'`.
- **`k3s/flux/<name>`** — Targeted Terraform apply for that service's DNS record(s) only. No Ansible. Requires its own dedicated step in `deploy.yml`.
- **`all`** — runs Terraform apply for everything, then loops through all Ansible playbooks in order: `adguard vault postgres redis portainer haproxy nfs k3s`.

---

## deploy.yml — step structure

```
1. checkout
2. Terraform Init          (skipped for k3s/flux)
3. Terraform Apply         (skipped for k3s/flux and all k3s/flux/<name>)
4. Terraform Apply (<name> DNS)   ← one step per k3s/flux/<name> service
   ...
5. Write SSH key
6. Install Python deps     (python3-passlib)
7. Run Ansible             (skipped for proxmox-dns and all k3s/flux/*)
```

Steps 3 and 7 use long `if` conditions that **explicitly exclude** every `k3s/flux/<name>` option. When a new in-cluster service is added, its name must be appended to both conditions.

### Terraform Apply vars (deploy + destroy)

Every `terraform apply` / `terraform destroy` passes the same core vars:
```
-var proxmox_endpoint="..."
-var proxmox_username="..."
-var proxmox_password="..."
-var ssh_public_key="..."
-var cloudflare_api_token="..."
```

Public services also pass:
```
-var haproxy_public_ip="..."
```

### Ansible vars

All Ansible playbooks receive all secrets via `-e` flags in a shared `run_playbook()` shell function — even if a specific playbook doesn't use all of them. This keeps the function uniform; unused vars are silently ignored by Ansible.

---

## destroy.yml — step structure

```
1. checkout
2. Resolve targets    ← case statement maps service name → -target=module.<name>
3. Terraform Init
4. Terraform Destroy  ← uses ${{ steps.ctx.outputs.targets }}
```

No Ansible step in destroy. Destroying the Terraform module removes the VM/LXC; Ansible state is not reversed.

---

## Local scripts

`.scripts/deploy.sh` and `.scripts/destroy.sh` are local equivalents of the two workflows.  
They read all secrets from **system environment variables** (set in `~/.zshrc` or `~/.zshenv`) — no `.env` file needed.  
Each script validates that required vars are present before running and prints a clear error listing any that are missing.

When adding a new service, keep `.scripts/deploy.sh` and `.scripts/destroy.sh` in sync with the workflow changes using the same checklist below.

---

## Checklist — adding a new infrastructure service (VM/LXC)

1. **`deploy.yml`** — add `<service>` to the `service` input choices.
2. **`deploy.yml`** — the generic "Terraform Apply" and "Run Ansible" steps already handle unknown services via `*)` fallback, so no extra step needed unless the service has special DNS-only behaviour.
3. **`destroy.yml`** — add `<service>` to the `service` input choices.
4. **`destroy.yml`** — add a line to the `case` statement: `<service>) echo "targets=-target=module.<service>" >> $GITHUB_OUTPUT ;;`
5. **`.scripts/deploy.sh`** — add `<service>` to the `case` block (mirrors the workflow deploy logic).
6. **`.scripts/destroy.sh`** — add `<service>` to the `TARGETS` case block (mirrors `destroy.yml`).
7. **`README.md`** — add the new service to the services table (IP, description).

## Checklist — removing an infrastructure service (VM/LXC)

1. **`deploy.yml`** — remove `<service>` from the `service` input choices.
2. **`destroy.yml`** — remove `<service>` from the `service` input choices and its `case` line.
3. **`.scripts/deploy.sh`** — remove the `<service>` case block.
4. **`.scripts/destroy.sh`** — remove the `<service>` case line.
5. **`README.md`** — remove the service from the services table.

## Checklist — adding a new in-cluster service (`k3s/flux/<name>`)

1. **`deploy.yml`** — add `k3s/flux/<name>` to the `service` input choices.
2. **`deploy.yml`** — add a dedicated step "Terraform Apply (`<name>` DNS)" with `if: inputs.service == 'k3s/flux/<name>'` and the correct `-target=cloudflare_record.<terraform_resource_name>`.
3. **`deploy.yml`** — append `&& inputs.service != 'k3s/flux/<name>'` to the `if` condition of both the generic "Terraform Apply" step and the "Run Ansible" step.
4. **`.scripts/deploy.sh`** — add a matching `k3s/flux/<name>)` case block with the same `-target` flags.
5. **`gitops/README.md`** — add the new service (hostname, namespace, description).
6. In-cluster services are **not added to `destroy.yml`** or `.scripts/destroy.sh` — Flux handles removal by deleting the gitops manifests; DNS records are cleaned up via a targeted `proxmox-dns` or direct Terraform run.

## Checklist — removing an in-cluster service (`k3s/flux/<name>`)

1. Delete the manifests under `gitops/clusters/homelab/apps/<public|private>/<name>/`.
2. **`deploy.yml`** — remove `k3s/flux/<name>` from the `service` input choices, its dedicated DNS step, and its exclusions from the generic "Terraform Apply" and "Run Ansible" `if` conditions.
3. **`.scripts/deploy.sh`** — remove the `k3s/flux/<name>` case block.
4. **`gitops/README.md`** — remove the service entry.
5. Clean up the DNS record: run a targeted Terraform destroy for `cloudflare_record.<name>` or remove it from `terraform/shared.tf` and apply.