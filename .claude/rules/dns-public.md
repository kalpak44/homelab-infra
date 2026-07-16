# Rules – Public Services

Public services are internet-facing and served through Cloudflare's CDN/WAF.

## Traffic path

```
Internet → Cloudflare CDN/WAF (proxied) → Traefik (k3s ingress, 192.168.1.120) → Pod
```

## DNS pattern

- **Hostname:** `<service>.pavel-usanli.online`
- **Cloudflare record:** A record, `proxied = true`
- **Target IP:** `var.public_wan_ip` (from `PUBLIC_WAN_IP` secret / env var)
- **Managed in:** its own dir at `terraform/cloudflare/dns/public/<name>/`
- **State key:** `homelab/cloudflare/dns/public/<name>.tfstate` on R2

Every public record has its own directory with `main.tf`, `variables.tf`, `providers.tf`, `versions.tf`, `backend.tf`.
Copy an existing dir when adding a new record.

```hcl
# terraform/cloudflare/dns/public/<name>/main.tf
data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "<name>" {
  zone_id = data.cloudflare_zone.this.id
  name    = "<name>"
  content = var.public_wan_ip
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

## Checklist – adding a new public service

1. Copy an existing DNS dir: `cp -r terraform/cloudflare/dns/public/nocobase terraform/cloudflare/dns/public/<name>` and
   edit `main.tf` + `backend.tf` (state key).
2. Add `dns/public/<name>` to the choice dropdowns in `.github/workflows/cloudflare-deploy.yml` and
   `cloudflare-destroy.yml`.
3. Add a description line in `terraform/Justfile`'s `list` recipe.
4. Create the k3s manifests at `gitops/clusters/homelab/apps/public/<name>/`: `namespace.yaml`, `deployment.yaml` (or
   `helmrelease.yaml`), `service.yaml`, `ingressroute.yaml` (template above).
5. If the app needs secrets, add a Vault secret and an `ExternalSecret` manifest.
6. Apply Terraform (`just deploy cloudflare dns/public/<name>` or via the workflow), then let Flux reconcile the k8s
   manifests.
7. Update `README.md` services table.