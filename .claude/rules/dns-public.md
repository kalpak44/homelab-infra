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