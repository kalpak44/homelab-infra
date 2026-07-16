# Infra Hardening Plan — Cloudflare Tunnel edge, dual Traefik, no HAProxy

Goal: single security perimeter (CrowdSec) covering every service — k3s pods and Portainer
containers, private and public — with zero WAN ports exposed and each orchestrator using its
native routing model.

## Target architecture

```
                                                ┌─ private *.internal (k3s)      → MetalLB 192.168.1.121 → Traefik-k3s
LAN client → AdGuard (192.168.1.2) ─────────────┤
                                                └─ private *.internal (portainer)→ 192.168.1.7            → Traefik-on-Portainer

Internet → Cloudflare (proxied) → Cloudflare Tunnel (cloudflared in k3s)
                                     ├─ k3s public hostnames   → Traefik-k3s :443           (CrowdSec middleware)
                                     └─ portainer public hosts → Traefik-on-Portainer :443  (CrowdSec plugin)
```

Four building blocks:

1. **No HAProxy.** Today it is a passthrough; it earns nothing.
2. **Cloudflare Tunnel** (`cloudflared` in k3s) replaces WAN NAT for all public traffic.
3. **Traefik-in-k3s stays** — existing `IngressRoute`s, cert-manager, CrowdSec plugin,
   MetalLB `120`/`121` split all untouched.
4. **Traefik-on-Portainer** — Docker provider, label-based routing for Portainer stacks.
   Bouncer plugin talks back to k3s CrowdSec LAPI over a private MetalLB VIP.

## Why this is stronger

- **Zero WAN ports.** Router NAT for `:80`/`:443` disappears; nothing is directly reachable
  from the internet.
- **One CrowdSec brain, two bouncers.** Engine + AppSec stay in k3s; both Traefiks bounce
  against it. Public and private traffic — k3s or Portainer — hits the same policy.
- **Cloudflare Access** gates any public hostname (SSO / MFA / country / device posture)
  without app changes, once the tunnel is live.
- **Each orchestrator uses native routing.** k3s → `IngressRoute` in Flux. Portainer →
  Docker labels in the stack file. No `ExternalName` drift between where a container is
  defined and where its route is defined.
- **Cert story simplifies.** Cloudflare terminates public TLS; origin runs with whatever
  Traefik-issued LE certs (CF Full mode). Internal `*.internal` stays on ACME DNS-01 as
  today.
- **Blast radius shrinks.** A k3s outage no longer takes Portainer routing with it; the
  Portainer Traefik is independent on `192.168.1.7`.

## Trade-offs (known and accepted)

- Cloudflare becomes the hard dependency for public reachability. It already proxies
  everything, so this deepens rather than introduces the dependency. If independent
  fallback is important, keep a WireGuard path.
- Two Traefik instances to keep on matching versions — small ops cost, both declarative.
- `cloudflared` adds one more workload; lifecycle is trivial via Flux HelmRelease.

---

## Migration steps

Each step is independently deployable and reversible. Do them in order; validate before
moving on.

### 1. Retire HAProxy

**Delete:**
- `terraform/proxmox/haproxy-lxc/`
- `ansible/proxmox/haproxy-lxc/`
- HAProxy host entry in `ansible/inventories/hosts.yml`
- `haproxy-lxc` option in `proxmox-deploy.yml`, `proxmox-destroy.yml`,
  `ansible-configure.yml`
- HAProxy description lines in `terraform/Justfile` + `ansible/Justfile` `list` recipes
- HAProxy row in `README.md` services table
- HAProxy card in `gitops/clusters/homelab/apps/private/private-home-page/index.html`
  (block at lines 124–141 — the `192.168.1.109:8404/stats` link)
- `HAPROXY_STATS_USER`, `HAPROXY_STATS_PASSWORD` from repo secrets (post-destroy)

**Modify:**
- `gitops/clusters/homelab/infrastructure/traefik-config/helmchartconfig.yaml:58-60` —
  remove the `proxyProtocol.trustedIPs` block on `public-web-secure` (no more upstream
  PROXY-v2 injector once HAProxy is gone).
- Rename `haproxy_public_ip` → `public_wan_ip` across every
  `terraform/cloudflare/dns/public/*/` and workflow env (`TF_VAR_haproxy_public_ip` →
  `TF_VAR_public_wan_ip`). Secret `HAPROXY_PUBLIC_IP` → `PUBLIC_WAN_IP`.

**Do:** run `just destroy proxmox haproxy-lxc`, then apply the DNS records so Cloudflare
records still point at the WAN IP under the renamed var. Router NAT still targets
`192.168.1.109` at this point — we'll flip it in step 4. **Temporarily** update the router
NAT to point at `192.168.1.120` (Traefik-k3s public LB) to keep public traffic flowing.

### 2. Deploy Cloudflare Tunnel

**Create:**
- `gitops/clusters/homelab/infrastructure/cloudflared/`
  - `namespace.yaml` (namespace `cloudflared`)
  - `helmrepository.yaml` — `https://cloudflare.github.io/helm-charts`
  - `helmrelease.yaml` — `cloudflare/cloudflared`, values referencing a
    `cloudflared-credentials` Secret and an inline ingress config:
    ```yaml
    ingress:
      - hostname: "*.pavel-usanli.online"
        service: https://traefik.kube-system.svc.cluster.local:443
        originRequest:
          originServerName: "traefik.kube-system.svc.cluster.local"
          noTLSVerify: true          # or mount CA + set caPool
      - service: http_status:404
    ```
  - `externalsecret.yaml` — pull the tunnel credentials JSON from Vault at
    `secret/homelab/cloudflared/credentials` into Secret `cloudflared-credentials`
  - `kustomization.yaml`

**One-time on your workstation:**
```bash
cloudflared tunnel login
cloudflared tunnel create homelab
# Copy the generated ~/.cloudflared/<TUNNEL_ID>.json into Vault
```

Store the tunnel UUID somewhere permanent (README or `gitops/README.md`) — it's the
CNAME target for every public record.

### 3. Flip public DNS records

For each `terraform/cloudflare/dns/public/<name>/main.tf`, replace:

```hcl
resource "cloudflare_record" "<name>" {
  type    = "A"
  content = var.public_wan_ip
  proxied = true
}
```

with:

```hcl
resource "cloudflare_record" "<name>" {
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
}
```

Add `tunnel_id` to `variables.tf` in each dir and pass it via `TF_VAR_tunnel_id` in
`cloudflare-deploy.yml` / `cloudflare-destroy.yml`. Roll one record at a time
(`nocobase` first, monitor, then the rest). Update `.claude/rules/dns-public.md` template
to the CNAME form.

### 4. Kill the WAN NAT

Once every public hostname reaches its app through the tunnel: delete the router's
port-forward rules for `:80` and `:443`. The `public_wan_ip` variable can be retired at
this point (or repurposed as `management_wan_ip` if anything still needs it).

### 5. Expose CrowdSec LAPI + AppSec on the LAN

The Portainer Traefik bouncer runs outside k3s and needs to reach the LAPI + AppSec
services.

**Modify** `gitops/clusters/homelab/infrastructure/crowdsec/helmrelease.yaml` (and
`appsec-service.yaml`) — add a `Service type=LoadBalancer` with
```yaml
metadata:
  annotations:
    metallb.universe.tf/address-pool: homelab
    metallb.universe.tf/allow-shared-ip: crowdsec-lan
spec:
  loadBalancerIP: 192.168.1.122     # or share 121 via allow-shared-ip
```
Exposing:
- LAPI on `:8080`
- AppSec on `:7422`

Firewall via k3s NetworkPolicy to only `192.168.1.7/32`.

Add a bouncer API key in Vault, mirrored via `ExternalSecret`, so both k3s and Portainer
sides reference the same key.

### 6. Traefik-on-Portainer

**Create `portainer/stacks/traefik.yml`** — a Traefik container with:
- Docker provider (`/var/run/docker.sock` read-only)
- File provider for static config (bouncer plugin registration + certificatesResolvers)
- ACME DNS-01 via Cloudflare against the existing `CLOUDFLARE_API_TOKEN`
- CrowdSec bouncer plugin pointed at `192.168.1.122:8080` / `:7422`
- Persistent volume for `acme.json`
- Exposed on `192.168.1.7:80` and `192.168.1.7:443` (host network or explicit port maps)

**Retire** the existing per-VM nginx + certbot for the Portainer UI: give Portainer itself
a Traefik label like every other stack and let the shared Traefik handle it.

**Migrate one stack as pilot.** Take `portainer/stacks/registry.yml`, remove the raw
`8282:80` and `5000:5000` port maps, add labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.registry-ui.rule=Host(`registry.internal.pavel-usanli.online`)"
  - "traefik.http.routers.registry-ui.entrypoints=websecure"
  - "traefik.http.routers.registry-ui.tls.certresolver=cloudflare"
  - "traefik.http.services.registry-ui.loadbalancer.server.port=80"
```
Add a DNS record dir `terraform/cloudflare/dns/private/registry/` pointing to
`192.168.1.7`, wire it into the workflow dropdown and the `terraform/Justfile` list. Once
verified, migrate the remaining stacks (`torrents.yml`, then anything added later) the
same way.

### 7. (Optional) Cloudflare Access on sensitive public hostnames

Once tunnels are live, add Access policies for any hostname that shouldn't be world-open
(dashboards, admin UIs). Zero app changes required.

---

## Deliverables checklist

- [ ] Step 1 — HAProxy fully removed; Traefik `proxyProtocol` block removed;
      `haproxy_public_ip` → `public_wan_ip` rename applied
- [ ] Step 2 — `cloudflared` running in k3s; tunnel credentials in Vault
- [ ] Step 3 — every public DNS record is a CNAME to `<tunnel-id>.cfargotunnel.com`
- [ ] Step 4 — router `:80` / `:443` port-forwards deleted; validated from outside network
- [ ] Step 5 — LAPI + AppSec reachable on a private MetalLB VIP; bouncer key in Vault
- [ ] Step 6 — Traefik-on-Portainer running; registry stack migrated to labels; DNS
      record added; nginx-on-Portainer retired
- [ ] Step 7 — Cloudflare Access applied to at least one sensitive hostname as a proof