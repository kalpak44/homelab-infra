# Rules – Private (Internal) Services

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
- **Managed in:** its own dir at `terraform/cloudflare/dns/private/<name>/`
- **State key:** `homelab/cloudflare/dns/private/<name>.tfstate` on R2

Every private record has its own directory. Copy an existing dir when adding a new record.

```hcl
# terraform/cloudflare/dns/private/<name>/main.tf
data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "<name>" {
  zone_id = data.cloudflare_zone.this.id
  name    = "<name>.internal"
  content = "192.168.1.<x>"   # LAN IP of the service (or 192.168.1.121 for in-cluster)
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

Handled by **certbot** with the Cloudflare DNS plugin (provisioned via each service's Ansible role under
`ansible/proxmox/<name>/roles/<role>/`).
Credentials stored at `/etc/letsencrypt/cloudflare.ini` on each host.
DNS propagation delay: 30 s.

## Checklist – adding a new private service

### In-cluster (k3s) service

1. Copy an existing DNS dir: `cp -r terraform/cloudflare/dns/private/traefik terraform/cloudflare/dns/private/<name>`,
   edit `main.tf` (`content = "192.168.1.121"`) and `backend.tf` (state key).
2. Add `dns/private/<name>` to the dropdowns in `.github/workflows/cloudflare-{deploy,destroy}.yml`.
3. Add a description line in `terraform/Justfile`'s `list` recipe.
4. Create `gitops/clusters/homelab/apps/private/<name>/`: `namespace.yaml`, `deployment.yaml` (or `helmrelease.yaml`),
   `service.yaml`, `ingressroute.yaml` (template above).
5. Apply Terraform (`just deploy cloudflare dns/private/<name>`), then let Flux reconcile.
6. Update `gitops/README.md` and `README.md` if applicable.

### Standalone VM / LXC service

1. Copy an existing DNS dir (e.g. `dns/private/adguard`), edit `main.tf` (`content = "<LAN IP>"`) and `backend.tf`.
2. Copy an existing Proxmox dir (`terraform/proxmox/adguard-lxc` or `proxmox/portainer-vm`), edit `main.tf` for the new
   host + `backend.tf`.
3. Copy the matching Ansible dir (`ansible/proxmox/adguard-lxc` etc.), edit playbook + role for the new service. Include
   certbot with the Cloudflare DNS plugin for TLS if the service serves HTTPS.
4. Add the host to `ansible/inventories/hosts.yml`.
5. Add the new resource name to every relevant workflow dropdown (`cloudflare-{deploy,destroy}.yml`,
   `proxmox-{deploy,destroy}.yml`, `ansible-configure.yml`) and the two Justfiles' `list` recipes.
6. Apply order: `just deploy cloudflare dns/private/<name>` → `just deploy proxmox <name>` → `just configure <name>`.
7. Update `README.md` services table.