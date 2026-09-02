# Rules – Public Services

Public services are internet-facing and routed through a Cloudflare Zero Trust tunnel — no open WAN ports required.

## Traffic path

```
Internet → Cloudflare edge → Cloudflare Tunnel → cloudflared LXC (192.168.1.10) → Traefik (192.168.1.120) → Pod
```

## DNS + tunnel pattern

All public DNS records and tunnel ingress rules are managed together in **`terraform/cloudflare/shared/zero-trust/`**.
There are no individual `dns/public/<name>/` directories — that pattern is retired.

- **Hostname:** `<service>.pavel-usanli.online`
- **Cloudflare record:** CNAME, `proxied = true`, pointing at `<tunnel-id>.cfargotunnel.com`
- **Tunnel ingress rule:** routes `<service>.pavel-usanli.online` → `https://192.168.1.120` with `no_tls_verify = true`
- **Managed in:** `terraform/cloudflare/shared/zero-trust/main.tf` — add one entry to `local.public_k3s_apps`

```hcl
# terraform/cloudflare/shared/zero-trust/main.tf
locals {
  public_k3s_apps = {
    # key = DNS record name, value = full hostname for tunnel ingress
    "existing-app" = "existing-app.pavel-usanli.online"
    "<name>"       = "<name>.pavel-usanli.online"   # add here
  }
}
```

Both the CNAME record and the tunnel ingress rule are generated automatically from this map via `for_each`.
After editing, run `just deploy cloudflare shared/zero-trust` (or the **Cloudflare - Deploy** workflow).

## Multiple zones — one dir, one tunnel, one map per zone

`shared/zero-trust` manages **every** public zone, not just `pavel-usanli.online`. `proklinator.online` (registered
at GoDaddy, nameservers delegated to Cloudflare) is the second. A third zone follows the same three steps:

1. A `data "cloudflare_zone"` block for it.
2. Its own `local.<zone>_apps` map and a matching `cloudflare_record` resource keyed off that zone's `zone_id`.
3. Its hostnames folded into `local.all_hostnames`, which is what the ingress `dynamic` block iterates.

**Ingress rules are keyed by hostname, records by record name.** `local.all_hostnames` is built with
`concat(values(...))` rather than `merge(...)` precisely because `"www"` exists as a record name in both zones and
would collide in a merged map.

**Never split a zone into its own dir.** `cloudflare_zero_trust_tunnel_cloudflared_config` replaces a tunnel's
*entire* ingress rule list, so a second state managing the same tunnel silently deletes the first one's rules on
every apply. A separate dir was tried and removed: routing it without ingress rules meant weakening the catch-all
from `http_status:404` to a Traefik forward, which traded an explicit hostname allowlist for a second state file
and six extra Terraform files. One dir keeps the catch-all a real 404.

**One tunnel, therefore one token.** A tunnel token identifies exactly one tunnel, so a second tunnel would mean a
second `cloudflared` daemon on 192.168.1.10, a second systemd unit, and a second GitHub secret. `CLOUDFLARE_TUNNEL_TOKEN`
covers all zones; adding a zone requires no Ansible change and no cloudflared restart, because the tunnel is remotely
managed and the daemon pulls the new config itself.

**The Traefik ACME token must cover every zone.** DNS-01 runs through the `cloudflare-api-token` secret; without
`Zone:DNS:Edit` on the new zone, issuance fails for its hostnames. Harmless in practice — Cloudflare terminates TLS
at the edge and the origin runs `no_tls_verify = true` — but Traefik retries for ever and fills its log.

## Domains we don't host — Cloudflare for SaaS

A hostname on someone else's domain cannot just CNAME at one of ours. It resolves to our edge IPs, but the handshake
carries the customer's SNI, and with no zone to match it the edge rejects it (1016) before any routing happens. Adding
a `cloudflare_custom_hostname` in `terraform/cloudflare/shared/zero-trust/saas.tf` registers that SNI against our zone,
issues a DV certificate for it, and routes it to the fallback origin (`saas.pavel-usanli.online`) — which is an
ordinary proxied record pointing at the tunnel.

**The Host header survives the whole trip, so a custom hostname still needs a tunnel ingress rule.** `local.saas_customers`
is folded into both `all_hostnames` and `ingress_overrides` in `main.tf` for exactly that reason. Register the hostname
but forget the rule and TLS negotiates cleanly and the request dies on the catch-all 404 — which looks identical to a
DNS mistake and is why the two maps are wired from one source.

Validation is `method = "txt"`, not `http`: HTTP validation requires the customer's CNAME to be serving already, and it
can't serve until the certificate exists. TXT lets the customer stage every record in one pass and cut over once. Hand
them `terraform output saas_customer_onboarding` — the CNAME plus both validation records. Those records are computed
by Cloudflare and are often empty on the apply that created the hostname; re-read the output after a refresh.

**A customer domain that happens to sit in our own Cloudflare account must be DNS-only.** An orange-clouded record is
served by that zone's own proxy and never reaches the custom-hostname path (orange-to-orange needs separate
enablement). This is the case for the simulated `app.proklinator.online` customer, whose record is deliberately *not*
managed by Terraform — it stands in for a record at a provider we don't control.

**Zone-level protections apply to custom hostnames, but their referer checks do not.** Hotlink Protection is off on
`pavel-usanli.online` (`cloudflare_zone_settings_override` in `saas.tf`) because a custom hostname inherits the zone's
settings while the check still compares the `Referer` against *our* apex — so a customer's own page loading its own
favicon reads as hotlinking and gets a 1011 on every image extension, but only when a referer is sent, which makes it
look intermittent. Treat any zone-wide setting that keys off the request's hostname the same way before enabling it.

## Kubernetes manifest

- **Namespace:** `public`
- **Traefik entryPoint:** `public-web-secure`
- **TLS:** `certResolver: cloudflare` (cert-manager + Cloudflare DNS-01)
- **Manifests location:** `gitops/clusters/homelab/apps/public/<service>/`

IngressRoute template:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: <service>
  namespace: public
spec:
  entryPoints:
    - public-web-secure
  routes:
    - match: Host(`<service>.pavel-usanli.online`)
      kind: Rule
      services:
        - name: <service>
          port: 80
  tls:
    certResolver: cloudflare
```

## Checklist – adding a new public service

1. Add one entry to `local.public_k3s_apps` in `terraform/cloudflare/shared/zero-trust/main.tf`:
   ```hcl
   "<name>" = "<name>.pavel-usanli.online"
   ```
2. Apply: `just deploy cloudflare shared/zero-trust` (or **Cloudflare - Deploy** → `shared/zero-trust`).
3. Create the k3s manifests at `gitops/clusters/homelab/apps/public/<name>/`: `namespace.yaml`, `deployment.yaml` (or
   `helmrelease.yaml`), `service.yaml`, `ingressroute.yaml` (template above).
4. If the app needs secrets, add a Vault secret and an `ExternalSecret` manifest.
5. Let Flux reconcile the k8s manifests.
6. Update `README.md` services table.