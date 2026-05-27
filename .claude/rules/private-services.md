# Rules — Private (Internal) Services

Private services are accessible only on the home LAN. They are never proxied through Cloudflare.

## Traffic path

```
LAN client → AdGuard Home DNS (192.168.1.2) → resolves *.internal → LAN IP directly
```

For in-cluster services the LAN IP is a MetalLB address (192.168.1.121); Traefik handles ingress inside k3s.  
For standalone VMs/LXCs the LAN IP is the container's own address.

## DNS pattern

- **Hostname:** `<service>.internal`
- **Cloudflare record:** A record, `proxied = false`
- **Target IP:** LAN IP of the service
- **Managed in:** `terraform/shared.tf`

```hcl
resource "cloudflare_record" "<service>_internal" {
  zone_id = data.cloudflare_zone.this.id
  name    = "<service>.internal"
  value   = "192.168.1.<x>"   # LAN IP of the service
  type    = "A"
  proxied = false
}
```

> AdGuard Home at 192.168.1.2 is configured as the DNS server for the home network.
> All `*.internal` names resolve because Cloudflare holds the authoritative records (unproxied).

## Kubernetes manifest (in-cluster services only)

- **Namespace:** `private`
- **Traefik entryPoint:** `websecure`
- **TLS:** `certResolver: cloudflare` (cert-manager + Cloudflare DNS-01)
- **MetalLB LoadBalancer IP:** 192.168.1.121
- **Manifests location:** `gitops/clusters/homelab/apps/private/<service>/`

IngressRoute template:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: <service>
  namespace: private
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`<service>.internal`)
      kind: Rule
      services:
        - name: <service>
          port: 80
  tls:
    certResolver: cloudflare
```

## TLS for standalone VMs / LXCs

Handled by **certbot** with the Cloudflare DNS plugin (provisioned via Ansible role).  
Credentials stored at `/etc/letsencrypt/cloudflare.ini` on each host.  
DNS propagation delay: 30 s.

## Checklist — adding a new private service

### In-cluster (k3s) service
1. Add a `cloudflare_record` in `terraform/shared.tf` pointing to `192.168.1.121`, `proxied = false`.
2. Create `gitops/clusters/homelab/apps/private/<service>/` with at minimum:
   - `namespace.yaml`
   - `deployment.yaml` (or `helmrelease.yaml`)
   - `service.yaml`
   - `ingressroute.yaml` (use template above)
3. Apply Terraform for the DNS record, then let Flux reconcile.

### Standalone VM / LXC service
1. Add a `cloudflare_record` in `terraform/shared.tf` pointing to the container's LAN IP, `proxied = false`.
2. Add (or update) the Ansible role/playbook to install and configure the service.
3. Ensure the Ansible role includes certbot with the Cloudflare DNS plugin for TLS.
4. Apply Terraform for the DNS record, then run the Ansible playbook.