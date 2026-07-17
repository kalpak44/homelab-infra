# Infra Plan — Shared Edge for k3s, Portainer, and Standalone Services

Goal: introduce one shared HTTP/S edge for normal apps, keep k3s routing working
with minimal change, bring Portainer-hosted apps under the same edge over time,
and leave selected infra services direct.

## Current state

Verified from this repository:

- Public DNS records under `terraform/cloudflare/dns/public/` point at
  `var.public_wan_ip` and are `proxied = true`.
- Private DNS records for in-cluster Traefik-fronted services point at
  `192.168.1.121`.
- Private DNS records for standalone services point directly at their host IPs.
- k3s routing uses Traefik `IngressRoute` CRDs with `public-web-secure` and
  `private-web-secure`.
- k3s Traefik is exposed on MetalLB-backed IPs: public service `192.168.1.120`,
  private service `192.168.1.121`.
- k3s Traefik `private-web` (port 80 on `192.168.1.121`) redirects to
  `private-web-secure` (port 443 on `192.168.1.121`) — plain HTTP is not usable
  as a backend target from the edge.
- CrowdSec LAPI and AppSec are ClusterIP services inside k3s with no external
  LAN endpoint today.
- CrowdSec bouncer middleware is applied only on the `public-web-secure`
  entrypoint, not on `private-web-secure`.
- Portainer runs on `192.168.1.7`, with nginx terminating TLS and the Portainer
  container bound to `127.0.0.1:9000`.
- AdGuard, Vault, pgAdmin, RabbitMQ, and Portainer currently manage their own
  certificates on-host with certbot and the Cloudflare DNS plugin.
- `terraform/proxmox/traefik-lxc/` exists (LXC 210, `192.168.1.10`) and is
  wired into `proxmox-deploy.yml`, `proxmox-destroy.yml`, and
  `terraform/Justfile`. The Ansible layer is not yet created.

## Target state

- One new `Traefik` LXC acts as the shared edge for normal web apps.
- k3s keeps its current in-cluster Traefik.
- Public traffic goes through Cloudflare to the edge.
- Private internal web apps go through internal DNS to the edge.
- Direct infra such as AdGuard, Vault, Proxmox, and database endpoints stay
  direct unless there is a specific reason to front them.
- Edge-managed certificates cover:
  - `pavel-usanli.online`
  - `*.pavel-usanli.online`
  - `*.internal.pavel-usanli.online`

Important:

- `*.pavel-usanli.online` does not cover `pavel-usanli.online`.
- The root website therefore needs the apex name included explicitly.

## Design decisions

These decisions resolve gaps in the original plan and must not be re-opened
without updating the affected steps.

### Edge → k3s backend protocol

The edge forwards to k3s Traefik via **HTTPS with `insecureSkipVerify: true`**
on a named `serversTransport` in the edge file provider.

Reason: `private-web` (port 80) redirects immediately to HTTPS so plain HTTP
is not usable as a backend target. The k3s Traefik cert is a valid Let's
Encrypt cert but is issued for hostnames, not the MetalLB IP
(`192.168.1.121`), so standard TLS verification fails. `insecureSkipVerify`
on an internal LAN hop is acceptable — the cert is still used for encryption,
just not for identity verification at this hop.

Concretely, define one `ServersTransport` in the edge file provider:

```yaml
http:
  serversTransports:
    k3s-private:
      insecureSkipVerify: true
```

All edge routes that target k3s private apps reference this transport.

### Edge dashboard hostname

The edge Traefik dashboard uses **`traefik-edge.internal.pavel-usanli.online`**,
served by a new DNS record at `terraform/cloudflare/dns/private/traefik-edge/`
pointing at `192.168.1.10`.

Reason: `terraform/cloudflare/dns/private/traefik/` already exists and points
at the in-cluster Traefik dashboard on `192.168.1.121`. Taking it over during
bootstrap would break the in-cluster dashboard before the edge is proven.
`traefik-edge.internal` is a new, distinct record with no conflict.

### CrowdSec LAPI and AppSec LAN exposure

Expose LAPI and AppSec via a **MetalLB `LoadBalancer` Service at
`192.168.1.122`** in a new GitOps manifest
`gitops/clusters/homelab/infrastructure/crowdsec/lxc-service.yaml`.

Ports on `192.168.1.122`:
- `8080` — LAPI (HTTP)
- `7422` — AppSec

Reason: MetalLB is the existing pattern for stable LAN-reachable IPs in this
cluster. A dedicated IP keeps LAPI/AppSec separate from the Traefik VIPs and
avoids port collisions. `192.168.1.122` is within the pool `192.168.1.120–130`.

### CrowdSec bouncer key for the edge

The edge Traefik needs its own bouncer key separate from the in-cluster
`BOUNCER_KEY_traefik`.

- Vault path: `secret/crowdsec/bouncer-key-edge`
- GitHub Actions secret: `CROWDSEC_BOUNCER_KEY_EDGE`
- Plumbed through `ansible-configure.yml` env block to the `traefik-lxc` role.
- The key is registered in CrowdSec LAPI during the `just configure traefik-lxc`
  run (an Ansible task that calls `cscli bouncers add traefik-edge`).

### Cloudflare Tunnel Terraform structure

- Terraform dir: `terraform/cloudflare/shared/cloudflare-tunnel/`
- State key: `homelab/cloudflare/shared/cloudflare-tunnel.tfstate`
- New GitHub Actions secret: `CLOUDFLARE_TUNNEL_TOKEN`
- Added to `cloudflare-deploy.yml` / `cloudflare-destroy.yml` dropdowns and
  `terraform/Justfile` list.
- The `cloudflared` daemon runs on the edge LXC, managed by a new Ansible role
  `ansible/proxmox/traefik-lxc/roles/cloudflared/`. The token is passed via
  `ansible-configure.yml` env block.

---

## Step-by-step plan

### 1. Keep the current k3s Traefik model unchanged

Do not start by changing GitOps app routing.

Reason:

- current apps already depend on Traefik `IngressRoute`
- current public/private entrypoints already exist
- this lets the edge be added without rewriting cluster routing first

Validation:

- current public apps still resolve through Cloudflare
- current private apps still resolve through `192.168.1.121`
- no GitOps app manifests need to change yet

### 2. Complete the `traefik-lxc` Proxmox service scaffolding

The Terraform half is done. Complete the remaining pieces:

Done:
- `terraform/proxmox/traefik-lxc/` (LXC 210, `192.168.1.10`)
- `traefik-lxc` in `proxmox-deploy.yml` and `proxmox-destroy.yml`
- `traefik-lxc` description in `terraform/Justfile` list

Still needed:
- add `ansible/proxmox/traefik-lxc/playbook.yml` + `roles/traefik/`
- add `192.168.1.10` host to `ansible/inventories/hosts.yml` under `lxc`
- add `traefik-lxc` to `.github/workflows/ansible-configure.yml` options
- add `CLOUDFLARE_API_TOKEN`, `LETSENCRYPT_EMAIL`, and
  `CROWDSEC_BOUNCER_KEY_EDGE` to the `ansible-configure.yml` env block (they
  are already present for other roles but verify)
- add `traefik-lxc` description to `ansible/Justfile` list
- add `traefik-lxc` row to `README.md` services table

Validation:

- `just deploy proxmox traefik-lxc` provisions the LXC
- the LXC is reachable on LAN at `192.168.1.10`
- `just configure traefik-lxc` can target it

### 3. Install and configure Traefik on the new LXC

The LXC should run Traefik as a systemd service (binary install, not Docker).

The initial Traefik setup should include:

- `web` (80) and `websecure` (443) entrypoints
- file provider pointing at `/etc/traefik/conf.d/`
- ACME DNS-01 with Cloudflare for certificate issuance
- access logging to `/var/log/traefik/access.log` (JSON, for CrowdSec later)
- dashboard on `traefik-edge.internal.pavel-usanli.online` (see design
  decisions — this is a new record, not the existing in-cluster one)

Certificate scope:

- `pavel-usanli.online`
- `*.pavel-usanli.online`
- `*.internal.pavel-usanli.online`

Additional file provider config needed at this step:

```yaml
http:
  serversTransports:
    k3s-private:
      insecureSkipVerify: true
```

Also add `terraform/cloudflare/dns/private/traefik-edge/` pointing at
`192.168.1.10` and wire it into `cloudflare-{deploy,destroy}.yml` dropdowns
and `terraform/Justfile` list.

Validation:

- Traefik starts cleanly
- certificates issue successfully
- `traefik-edge.internal.pavel-usanli.online` dashboard is reachable privately
- logs appear in `/var/log/traefik/access.log`

### 4. Decide the first private apps to move behind the edge

Start with the current k3s private web apps that already live behind the
in-cluster Traefik.

Good first candidates from the repo:

- `headlamp.internal.pavel-usanli.online`
- `crowdsec.internal.pavel-usanli.online`
- `home.internal.pavel-usanli.online`

Note: `traefik.internal.pavel-usanli.online` (in-cluster dashboard) stays
pointing at `192.168.1.121` for now. It will be moved in a later step if
desired. Do not move it during the first migration wave.

Do not move direct infra in this step.

Validation:

- an explicit list of first hostnames is agreed
- direct infra hostnames remain unchanged

### 5. Point selected private DNS records to the edge LXC

For each chosen private hostname, change the Cloudflare private DNS record from
`192.168.1.121` to `192.168.1.10` (the edge LXC).

Expected record groups for the first wave:

- `terraform/cloudflare/dns/private/headlamp/`
- `terraform/cloudflare/dns/private/crowdsec-web-ui/`
- `terraform/cloudflare/dns/private/private-home-page/`

Do this one hostname at a time.

Validation:

- each hostname resolves to `192.168.1.10`
- the edge forwards to k3s correctly
- the underlying `IngressRoute` stays unchanged

### 6. Add edge routes for k3s private apps

Create edge routes in `/etc/traefik/conf.d/` on the edge LXC that match each
moved private hostname and proxy to the k3s private VIP backend.

Backend target for all k3s private apps: `https://192.168.1.121:443`

All routes targeting k3s must reference the `k3s-private` serversTransport
(see design decisions) to skip TLS verification on the internal hop.

Keep the in-cluster Traefik semantics intact:

- edge matches the hostname and forwards with the original `Host` header
- k3s Traefik still dispatches to the final service/pod via its `IngressRoute`
- no app manifest rewrite needed

Validation:

- private k3s apps work through the edge
- there is no app-manifest rewrite
- private app TLS is served by the edge cert (not k3s cert — clients see the
  edge wildcard cert)

### 7. Add Cloudflare Tunnel support for public entry

Add a Cloudflare Tunnel so public traffic no longer requires WAN NAT on 80/443.

Repo changes (see design decisions for specifics):

- add `terraform/cloudflare/shared/cloudflare-tunnel/` with `main.tf`,
  `backend.tf` (key `homelab/cloudflare/shared/cloudflare-tunnel.tfstate`),
  `variables.tf`, `providers.tf`, `versions.tf`
- add `shared/cloudflare-tunnel` to `cloudflare-deploy.yml` and
  `cloudflare-destroy.yml` dropdowns
- add description line to `terraform/Justfile` list
- add new GitHub Actions secret `CLOUDFLARE_TUNNEL_TOKEN`
- add `cloudflared` Ansible role at `ansible/proxmox/traefik-lxc/roles/cloudflared/`
  that installs and configures the `cloudflared` daemon as a systemd service,
  reading the token from the `CLOUDFLARE_TUNNEL_TOKEN` env var
- add `CLOUDFLARE_TUNNEL_TOKEN` to the `ansible-configure.yml` env block

The public flow becomes:

`Internet -> Cloudflare Tunnel -> edge LXC -> backend`

Validation:

- one public hostname works through the tunnel
- the edge receives the request
- the backend app still works unchanged

### 8. Move public app DNS from WAN IP to the edge path

After the tunnel is working, migrate public hostnames one at a time so they no
longer rely on the current direct WAN-IP path.

Start with one service, validate it, then continue.

The root website must be handled explicitly:

- `pavel-usanli.online`
- `www.pavel-usanli.online`

Validation:

- the root personal site works through the edge path
- another public app works through the edge path
- certificate coverage is correct for both apex and wildcard hosts

### 9. Expose CrowdSec LAPI and AppSec for the edge

Add a MetalLB `LoadBalancer` Service that gives the edge LXC a stable LAN
address to reach CrowdSec.

New GitOps manifest: `gitops/clusters/homelab/infrastructure/crowdsec/lxc-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: crowdsec-lxc
  namespace: crowdsec
  annotations:
    metallb.universe.tf/address-pool: homelab
    metallb.universe.tf/loadBalancerIPs: 192.168.1.122
spec:
  type: LoadBalancer
  selector:
    k8s-app: crowdsec
    type: lapi
    version: v1
  ports:
    - name: lapi
      port: 8080
      targetPort: 8080
    - name: appsec
      port: 7422
      targetPort: 7422
```

The edge LXC reaches CrowdSec at:
- LAPI: `http://192.168.1.122:8080`
- AppSec: `http://192.168.1.122:7422`

Bouncer key provisioning:
- Store the key at Vault path `secret/crowdsec/bouncer-key-edge`
- Add GitHub Actions secret `CROWDSEC_BOUNCER_KEY_EDGE`
- Add `CROWDSEC_BOUNCER_KEY_EDGE` to `ansible-configure.yml` env block
- The `traefik-lxc` Ansible role registers the bouncer key by calling
  `cscli bouncers add traefik-edge --key $CROWDSEC_BOUNCER_KEY_EDGE` via an
  Ansible task that shells into the k3s LAPI pod (or via the exposed
  `192.168.1.122:8080` endpoint once it is up)

Validation:

- `192.168.1.122:8080` is reachable from the edge LXC
- the edge bouncer plugin initializes successfully against the LAPI
- `192.168.1.122:7422` (AppSec) is reachable from the edge LXC

### 10. Feed edge Traefik logs into CrowdSec

Do not stop at only wiring the bouncer.

Because the edge will see Portainer and standalone-app traffic that never hits
the k3s Traefik pods, CrowdSec must also see edge traffic.

Preferred approach: **CrowdSec agent on the edge LXC** parsing
`/var/log/traefik/access.log` and forwarding decisions to the LAPI at
`192.168.1.122:8080`.

This is added as a second Ansible role (`crowdsec-agent`) inside
`ansible/proxmox/traefik-lxc/roles/`, installed and configured to:
- parse the Traefik access log (`crowdsecurity/traefik` collection)
- connect to LAPI at `http://192.168.1.122:8080`

Validation:

- a request through an edge-fronted private app reaches CrowdSec logic
- a request through an edge-fronted public app reaches CrowdSec logic

### 11. Bring Portainer UI behind the edge

First proxy the existing Portainer VM shape as-is.

Current verified runtime shape:

- nginx on the VM terminates TLS
- Portainer container is only on `127.0.0.1:9000`

The edge backend for Portainer is the Portainer VM nginx, which already holds
a valid Let's Encrypt cert. The edge→Portainer hop is HTTPS, and because the
cert is issued for `portainer.internal.pavel-usanli.online` (not an IP), a
named `serversTransport` with `insecureSkipVerify: true` is required here as
well (same pattern as `k3s-private` — add a `portainer-vm` transport or reuse
the existing one).

So the first safe hop is:

`Edge Traefik LXC -> Portainer VM nginx (https://192.168.1.7:443)`

Do not try to proxy directly to `127.0.0.1:9000` from the edge LXC.

Validation:

- `portainer.internal.pavel-usanli.online` works through the edge if you decide
  to move it
- Portainer remains functional without changing the container binding yet

### 12. Bring selected Portainer-hosted apps behind the edge

For each Portainer-hosted web app:

- create an edge route
- create or update private DNS to point to the edge
- reduce raw published LAN ports where they are no longer needed

Do this one app at a time.

Validation:

- at least one Portainer-hosted app works through the edge
- unnecessary raw port exposure is reduced

### 13. Keep direct infra direct

Do not front everything by default.

Services that should remain direct unless there is a strong reason:

- `adguard.internal`
- `vault.internal`
- `proxmox.internal`
- database/service endpoints

These can keep their current on-host certificate model.

Validation:

- direct infra continues to work independently of the edge
- failure of the edge does not block core infra access

### 14. Remove WAN NAT for `80/443` only after the edge path is proven

Only do this after public apps are confirmed through Cloudflare Tunnel to the
edge.

Then:

- remove router NAT for `80/443`
- remove obsolete Terraform/public-DNS dependence on the direct WAN-IP path

Validation:

- public apps still work
- the WAN-IP-based public entry path is no longer required

## Result

At the end of this plan:

- normal web apps are fronted from one shared edge
- k3s keeps its current routing model
- Portainer apps can be brought under the same edge gradually
- CrowdSec enforcement happens at the edge and sees edge traffic
- selected infra services stay direct
- the root website at `pavel-usanli.online` is included explicitly in the
  certificate strategy