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
- k3s Traefik is exposed on MetalLB-backed IPs including `192.168.1.120` and
  `192.168.1.121`.
- CrowdSec currently integrates with the in-cluster Traefik path.
- Portainer runs on `192.168.1.7`, with nginx terminating TLS and the Portainer
  container bound to `127.0.0.1:9000`.
- AdGuard, Vault, pgAdmin, RabbitMQ, and Portainer currently manage their own
  certificates on-host with certbot and the Cloudflare DNS plugin.

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

## Traffic model

Public:

`Internet -> Cloudflare proxy or Tunnel -> Edge Traefik LXC -> backend`

Private:

`LAN client -> internal DNS -> Edge Traefik LXC -> backend`

Backends behind the edge can be:

- k3s Traefik VIPs
- Portainer VM endpoints
- future standalone web apps on LXCs/VMs

Backends that stay direct:

- AdGuard
- Vault
- Proxmox
- direct database/service endpoints

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

### 2. Add a new Proxmox service for `traefik-lxc`

Create a new Proxmox-managed service following the existing repo pattern.

Repo changes:

- add `terraform/proxmox/traefik-lxc/`
- add `ansible/proxmox/traefik-lxc/`
- add the host to `ansible/inventories/hosts.yml`
- add `traefik-lxc` to:
  - `.github/workflows/proxmox-deploy.yml`
  - `.github/workflows/proxmox-destroy.yml`
  - `.github/workflows/ansible-configure.yml`
- add list entries to:
  - `terraform/Justfile`
  - `ansible/Justfile`
- update `README.md`

Validation:

- `just deploy proxmox traefik-lxc` works
- the LXC is reachable on LAN
- `just configure traefik-lxc` can target it

### 3. Install and configure Traefik on the new LXC

The LXC should run Traefik as a systemd service.

The initial Traefik setup should include:

- `web` and `websecure` entrypoints
- file provider configuration
- upstreams for k3s VIPs
- ACME DNS-01 with Cloudflare
- access logging
- dashboard on a private hostname

Certificate scope:

- `pavel-usanli.online`
- `*.pavel-usanli.online`
- `*.internal.pavel-usanli.online`

Validation:

- Traefik starts cleanly
- certificates issue successfully
- dashboard is reachable privately
- logs show requests correctly

### 4. Decide the first private apps to move behind the edge

Start with the current k3s private web apps that already live behind the
in-cluster Traefik.

Good first candidates from the repo:

- `traefik.internal.pavel-usanli.online`
- `headlamp.internal.pavel-usanli.online`
- `crowdsec.internal.pavel-usanli.online`
- `home.internal.pavel-usanli.online`
- `data-source-example.internal.pavel-usanli.online`

Do not move direct infra in this step.

Validation:

- explicit list of first hostnames is agreed
- direct infra hostnames remain unchanged

### 5. Point selected private DNS records to the edge LXC

For each chosen private hostname, change the Cloudflare private DNS record from
`192.168.1.121` to the new edge LXC IP.

Expected record groups:

- `terraform/cloudflare/dns/private/traefik/`
- `terraform/cloudflare/dns/private/headlamp/`
- `terraform/cloudflare/dns/private/crowdsec-web-ui/`
- `terraform/cloudflare/dns/private/private-home-page/`
- `terraform/cloudflare/dns/private/data-source-connector-example/`

Do this one hostname at a time.

Validation:

- each hostname resolves to the edge LXC
- the edge forwards to k3s correctly
- the underlying `IngressRoute` stays unchanged

### 6. Add edge routes for k3s private apps

Create edge routes that match each moved private hostname and proxy to the
appropriate k3s private VIP/backend.

Keep the in-cluster Traefik semantics intact:

- edge matches the hostname
- edge forwards to k3s
- k3s Traefik still dispatches to the final service/pod

Validation:

- private k3s apps work through the edge
- there is no app-manifest rewrite
- private app TLS is served by the edge

### 7. Add Cloudflare Tunnel support for public entry

If the goal remains zero inbound WAN ports, add Cloudflare Tunnel for the edge
LXC.

Repo changes:

- add a Cloudflare shared Terraform resource for the tunnel
- add workflow dropdown entries
- add `Justfile` list entries
- store the tunnel token in the current secret flow you use for Ansible

The public flow should become:

`Cloudflare -> edge LXC -> backend`

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

### 9. Expose CrowdSec services so the edge can use them

The edge needs a reliable private path to CrowdSec LAPI/AppSec.

Update the k3s CrowdSec side so the edge LXC can reach:

- LAPI
- AppSec

Keep this private to the LAN.

Validation:

- the edge can reach CrowdSec endpoints
- the edge bouncer/plugin can initialize successfully

### 10. Feed edge Traefik logs into CrowdSec

Do not stop at only wiring the bouncer.

Because the edge will see Portainer and standalone-app traffic that never hits
the k3s Traefik pods, CrowdSec must also see edge traffic.

Implement one of:

- CrowdSec agent on the edge LXC parsing Traefik logs
- log shipping from the edge into a central CrowdSec-consumable location

Validation:

- a request through an edge-fronted private app reaches CrowdSec logic
- a request through an edge-fronted public app reaches CrowdSec logic

### 11. Bring Portainer UI behind the edge

First proxy the existing Portainer VM shape as-is.

Current verified runtime shape:

- nginx on the VM terminates TLS
- Portainer container is only on `127.0.0.1:9000`

So the first safe hop is:

`Edge Traefik LXC -> Portainer VM nginx`

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

Only do this after public apps are confirmed through Cloudflare to the edge.

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
