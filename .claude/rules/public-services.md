# Rules — Public Services

Public services are internet-facing and served through Cloudflare's CDN/WAF.

## Traffic path

```
Internet → Cloudflare CDN/WAF (proxied) → HAProxy (192.168.1.109) → Traefik (k3s ingress) → Pod
```

## DNS pattern

- **Hostname:** `<service>.pavel-usanli.online`
- **Cloudflare record:** A record, `proxied = true`
- **Target IP:** `var.haproxy_public_ip` (stored in GitHub Secret `HAPROXY_PUBLIC_IP`)
- **Managed in:** `terraform/shared.tf`

```hcl
resource "cloudflare_record" "<service>" {
  zone_id = data.cloudflare_zone.this.id
  name    = "<service>"
  value   = var.haproxy_public_ip
  type    = "A"
  proxied = true
}
```

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

## Checklist — adding a new public service

1. Add a `cloudflare_record` in `terraform/shared.tf` (`proxied = true`).
2. Create `gitops/clusters/homelab/apps/public/<service>/` with at minimum:
   - `namespace.yaml`
   - `deployment.yaml` (or `helmrelease.yaml`)
   - `service.yaml`
   - `ingressroute.yaml` (use template above)
3. If the app needs secrets: add a Vault secret and an `ExternalSecret` manifest.
4. Apply Terraform to publish the DNS record, then let Flux reconcile the k8s manifests.