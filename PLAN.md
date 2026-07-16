# Infra Hardening Plan — Traefik LXC edge + Cloudflare Tunnel, all as code

Goal: one security perimeter (CrowdSec) covering every service — k3s pods, Portainer
containers, standalone LXCs — with zero WAN ports exposed and the entire edge
described in Terraform + Ansible.

## Target architecture

```
                                                  ┌── *.internal.pavel-usanli.online per-service records:
                                                  │     • adguard.internal   → 192.168.1.2    (direct)
                                                  │     • vault.internal     → 192.168.1.3    (direct)
LAN client → AdGuard (192.168.1.2) ───────────────┤     • ...  (standalone LXCs/VMs)
                                                  │     • nocobase.internal  → 192.168.1.10   (Traefik LXC)
                                                  │     • headlamp.internal  → 192.168.1.10   (Traefik LXC)
                                                  │     • ...  (Traefik-fronted)
                                                  ↓
                                              Traefik LXC (192.168.1.10)
                                                  ↑
Internet → Cloudflare (proxied) → CF Tunnel → cloudflared (on Traefik LXC) → Traefik (localhost:443)
                                                  │
                                                  │  (file provider routes)
                                                  ├── k3s Traefik LB (192.168.1.120:443) → in-cluster Traefik → pod
                                                  ├── Portainer VM (192.168.1.7:<port>)  → docker container
                                                  └── future LXC (192.168.1.<x>:<port>)
```

Four building blocks, all described as code:

1. **Traefik LXC** — new Proxmox LXC on `192.168.1.10`. Provisioned by Terraform,
   configured by Ansible. Runs Traefik + cloudflared as systemd services.
2. **Cloudflare Tunnel** — created and configured entirely via Terraform
   (`cloudflare_tunnel` + `cloudflare_tunnel_config`). Ingress rule sends
   `*.pavel-usanli.online → https://localhost:443` on the LXC.
3. **k3s in-cluster Traefik stays** as an internal dispatcher for k3s workloads.
   LXC Traefik forwards k3s-bound requests to the in-cluster LB IP; existing
   `IngressRoute` CRDs and Flux-managed manifests keep working unchanged.
4. **CrowdSec engine stays in k3s** but its LAPI + AppSec get exposed on a private
   MetalLB VIP so the LXC-side bouncer can reach them. The bouncer plugin runs on
   LXC Traefik (moved out of in-cluster Traefik).

## Why this is stronger

- **Zero WAN ports.** Router NAT for `:80` / `:443` disappears. The tunnel is the
  only public path.
- **One CrowdSec bouncer, single edge.** Every request — public or private, k3s or
  Portainer or standalone — traverses LXC Traefik and its bouncer.
- **All infra as code.** LXC (Terraform), tunnel (Terraform), DNS (Terraform),
  Traefik + cloudflared + routes (Ansible). One repo, one pattern per layer,
  reviewable diffs.
- **Cloudflare Access** can gate any public hostname with SSO / MFA / country /
  device posture once the tunnel is live.
- **Fits the existing convention.** Traefik LXC slots into the
  `terraform/proxmox/<name>-lxc/` + `ansible/proxmox/<name>-lxc/` pattern used by
  every other service in the repo.

## Trade-offs (known and accepted)

- Two Traefik instances (LXC edge + k3s internal). Boundary is honest (edge vs.
  internal dispatcher) but does mean two config surfaces stay in step.
- LXC Traefik routes live in an Ansible template — not container labels. Adding a
  Traefik-fronted service means editing
  `ansible/proxmox/traefik-lxc/roles/traefik/templates/dynamic.yml.j2` plus a new
  per-service DNS dir.
- Cloudflare becomes the hard dependency for public reachability. It already
  proxies — this deepens rather than introduces the dependency.

---

## Migration steps

Each step is independently deployable and reversible. Do them in order; validate
before moving on.

### 1. Retire HAProxy ✅ done (commit `cb89323`)

### 2. Provision the Traefik LXC (Terraform)

Clone `terraform/proxmox/adguard-lxc/` → `terraform/proxmox/traefik-lxc/`:

- LXC ID `210` (or next free), 2 vCPU / 1 GB RAM / 8 GB disk
- Static IP `192.168.1.10`
- State key: `homelab/proxmox/traefik-lxc.tfstate`

**Wire it in:**
- `.github/workflows/proxmox-deploy.yml` / `proxmox-destroy.yml` — add `traefik-lxc`
- `.github/workflows/ansible-configure.yml` — add `traefik-lxc`
- `terraform/Justfile` + `ansible/Justfile` `list` recipes
- `ansible/inventories/hosts.yml` — new host `traefik: 192.168.1.10`
- `README.md` services table

**Deploy:** `just deploy proxmox traefik-lxc`.

### 3. Create the Cloudflare Tunnel (Terraform)

New dir `terraform/cloudflare/shared/cloudflare-tunnel/`:

- `main.tf` — `cloudflare_tunnel.homelab` (with `random_password` for the secret)
  and `cloudflare_tunnel_config.homelab` — remotely-managed ingress:
  ```hcl
  config {
    ingress_rule {
      hostname = "*.pavel-usanli.online"
      service  = "https://localhost:443"
      origin_request {
        origin_server_name = "traefik.internal.pavel-usanli.online"
        no_tls_verify      = true
      }
    }
    ingress_rule { service = "http_status:404" }
  }
  ```
- `outputs.tf` — `tunnel_id` (non-sensitive), `tunnel_token` (sensitive)
- `variables.tf` — adds `cloudflare_account_id`

**New GH secret + local env var:** `CLOUDFLARE_ACCOUNT_ID`. Wire into
`cloudflare-deploy.yml` / `-destroy.yml` env blocks and the `terraform/Justfile`
mapping (`export TF_VAR_cloudflare_account_id="${CLOUDFLARE_ACCOUNT_ID:-}"`).

**Wire it in:** add `shared/cloudflare-tunnel` to cloudflare workflow dropdowns
and `terraform/Justfile` list.

**Deploy:**
```bash
just deploy cloudflare shared/cloudflare-tunnel
terraform -chdir=terraform/cloudflare/shared/cloudflare-tunnel output tunnel_id       # save as GH secret TUNNEL_ID
terraform -chdir=terraform/cloudflare/shared/cloudflare-tunnel output -raw tunnel_token # paste into Vault at secret/homelab/cloudflared/token
```

### 4. Configure the Traefik LXC (Ansible)

New role `ansible/proxmox/traefik-lxc/roles/traefik/`:

- `tasks/main.yml` — install Traefik binary + systemd unit, install `cloudflared`
  binary + systemd unit, fetch tunnel token from Vault, template configs, enable
  services
- `templates/traefik.yml.j2` — static config: entryPoint `websecure` on `:443`,
  ACME DNS-01 via Cloudflare for `*.internal.pavel-usanli.online`, CrowdSec
  bouncer plugin registration, JSON access log
- `templates/dynamic.yml.j2` — file provider routes (k3s Traefik LB, Portainer
  VM, future LXCs)
- `templates/cloudflared.service.j2` — systemd unit running
  `cloudflared tunnel --no-autoupdate run --token <TOKEN>`
- `defaults/main.yml` — Traefik version, backend endpoints, Vault path for the
  token

**Configure:** `just configure traefik-lxc`.

**Validate:**
- `systemctl status traefik cloudflared` on the LXC
- Cloudflare Zero Trust dashboard shows the tunnel as HEALTHY (4 connections)
- `curl -k https://192.168.1.10/dashboard/` returns the Traefik UI

### 5. Point private DNS records at the Traefik LXC

For each `.internal` service routed through Traefik, flip `content` from
`192.168.1.121` → `192.168.1.10` in its per-service dir:

- `terraform/cloudflare/dns/private/traefik/main.tf`
- `terraform/cloudflare/dns/private/headlamp/main.tf`
- `terraform/cloudflare/dns/private/crowdsec-web-ui/main.tf`
- `terraform/cloudflare/dns/private/private-home-page/main.tf`
- `terraform/cloudflare/dns/private/data-source-connector-example/main.tf`

Any *new* Traefik-fronted hostname needs its own `terraform/cloudflare/dns/private/<name>/`
dir following the existing template (plus dropdown + Justfile list entry). One
DNS dir per hostname — the current convention.

Standalone services (adguard, vault, postgres, redis, rabbitmq, portainer, nfs,
proxmox) keep their existing dedicated records — they serve on their own boxes,
not through Traefik.

Apply one at a time: `just deploy cloudflare dns/private/<name>` — monitor.

### 6. Flip public DNS records to CNAME → tunnel

In every `terraform/cloudflare/dns/public/<name>/main.tf`, replace:
```hcl
type    = "A"
content = var.public_wan_ip
```
with:
```hcl
type    = "CNAME"
content = "${var.tunnel_id}.cfargotunnel.com"
```
Add `tunnel_id` to each `variables.tf`. Wire `TF_VAR_tunnel_id` (mapped from GH
secret `TUNNEL_ID`) in `terraform/Justfile` + cloudflare workflow env blocks.

Update `.claude/rules/dns-public.md` template to the CNAME form.

Roll one record at a time (`nocobase` first, monitor, then the rest).

### 7. Kill the WAN NAT

Once every public hostname reaches its app through the tunnel: delete the
router's port-forward rules for `:80` and `:443`. Retire the `PUBLIC_WAN_IP`
GH secret + `terraform/Justfile` mapping (and delete `public_wan_ip` from the
public DNS `variables.tf` files it's no longer used in).

### 8. Expose CrowdSec LAPI + AppSec on a private MetalLB VIP

Modify `gitops/clusters/homelab/infrastructure/crowdsec/`:
- Add `Service type=LoadBalancer` for `crowdsec-service` (`:8080`) and
  `crowdsec-appsec` (`:7422`) with
  ```yaml
  metadata:
    annotations:
      metallb.universe.tf/address-pool: homelab
      metallb.universe.tf/allow-shared-ip: crowdsec-lan
  spec:
    loadBalancerIP: 192.168.1.122
  ```
- Bouncer API key stored in Vault; both the LXC bouncer and any in-cluster
  consumers reference the same key via `ExternalSecret`.

Update the LXC Traefik CrowdSec plugin config (`templates/traefik.yml.j2`) to
point at `192.168.1.122:8080` (LAPI) and `:7422` (AppSec).

Once LXC bouncer traffic is confirmed reaching LAPI, **remove** the CrowdSec
middleware from `gitops/.../traefik-config/helmchartconfig.yaml` — the bouncer
lives at the LXC edge now; in-cluster Traefik is a pure internal dispatcher.

### 9. Migrate Portainer containers behind LXC Traefik

For each raw-port-exposed Portainer stack (registry, torrents, …):

1. Add a route block in
   `ansible/proxmox/traefik-lxc/roles/traefik/templates/dynamic.yml.j2`:
   ```yaml
   http:
     routers:
       registry:
         rule: "Host(`registry.internal.pavel-usanli.online`)"
         entryPoints: [websecure]
         service: registry
         tls:
           certResolver: cloudflare
     services:
       registry:
         loadBalancer:
           servers:
             - url: "http://192.168.1.7:8282"
   ```
2. New DNS dir `terraform/cloudflare/dns/private/registry/` with
   `content = "192.168.1.10"`. Wire into dropdowns + `terraform/Justfile` list.
3. In `portainer/stacks/<name>.yml`, drop the raw `<port>:<port>` map (or bind
   to `127.0.0.1:<port>` if you still want local dev access on the VM).
4. Apply: `just deploy cloudflare dns/private/<name>` and
   `just configure traefik-lxc`.

Retire the nginx-on-Portainer role once Portainer itself is fronted by LXC
Traefik (a route pointing at `http://192.168.1.7:<portainer_internal_port>`).

### 10. (Optional) Cloudflare Access on sensitive public hostnames

Once tunnels are live, add Access policies for hostnames that shouldn't be
world-open (dashboards, admin UIs). Zero app changes.

---

## Deliverables checklist

- [x] Step 1 — HAProxy fully removed
- [ ] Step 2 — Traefik LXC provisioned via Terraform, reachable at `192.168.1.10`
- [ ] Step 3 — CF Tunnel created via Terraform; `TUNNEL_ID` GH secret set;
      tunnel token in Vault
- [ ] Step 4 — Ansible role installs Traefik + cloudflared; tunnel HEALTHY in CF
- [ ] Step 5 — every Traefik-fronted `.internal` DNS record points at `192.168.1.10`
- [ ] Step 6 — every public DNS record is a CNAME to `<tunnel_id>.cfargotunnel.com`
- [ ] Step 7 — router `:80` / `:443` port-forwards deleted; verified externally;
      `PUBLIC_WAN_IP` retired
- [ ] Step 8 — LAPI + AppSec on a private MetalLB VIP; LXC bouncer bouncing;
      in-cluster Traefik CrowdSec middleware removed
- [ ] Step 9 — Portainer stacks fronted by LXC Traefik; nginx-on-Portainer retired
- [ ] Step 10 — Cloudflare Access on at least one sensitive hostname (proof)