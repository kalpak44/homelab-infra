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
- **Managed in:** one map, `local.internal_records` in `terraform/cloudflare/zones/pavel-usanli.online/internal/main.tf`
- **State key:** `homelab/cloudflare/zones/pavel-usanli.online/internal.tfstate` on R2

Every private record is one line in that map; a single `for_each` resource turns each into an unproxied A record.
Adding a record needs no new dir, dropdown entry or `just list` line.

```hcl
# terraform/cloudflare/zones/pavel-usanli.online/internal/main.tf
locals {
  internal_records = {
    # key = the label before .internal, value = LAN IP (192.168.1.121 for in-cluster)
    "<name>" = "192.168.1.<x>"   # add here
  }
}
```

The 20 per-record dirs under `dns/private/` were collapsed into this map; each record kept its state entry, moved
under `cloudflare_record.internal["<name>"]`, so nothing was recreated. Do not reintroduce a dir per record — it cost
five files, a state file, two dropdown entries and a `just list` line for a single A record.

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

1. Add `"<name>" = "192.168.1.121"` to `local.internal_records` in
   `terraform/cloudflare/zones/pavel-usanli.online/internal/main.tf`.
2. Create `gitops/clusters/homelab/apps/private/<name>/`: `namespace.yaml`, `deployment.yaml` (or `helmrelease.yaml`),
   `service.yaml`, `ingressroute.yaml` (template above).
3. Apply Terraform (`just deploy cloudflare zones/pavel-usanli.online/internal`), then let Flux reconcile.
4. Update `gitops/README.md` and `README.md` if applicable.

### Standalone VM / LXC service

1. Add `"<name>" = "<LAN IP>"` to `local.internal_records` in
   `terraform/cloudflare/zones/pavel-usanli.online/internal/main.tf`.
2. Copy an existing Proxmox dir (`terraform/proxmox/adguard-lxc` or `proxmox/portainer-vm`), edit `main.tf` for the new
   host + `backend.tf`.
3. Copy the matching Ansible dir (`ansible/proxmox/adguard-lxc` etc.), edit playbook + role for the new service. Include
   certbot with the Cloudflare DNS plugin for TLS if the service serves HTTPS.
4. Add the host to `ansible/inventories/hosts.yml`.
5. Add the new resource name to every relevant workflow dropdown (`proxmox-{deploy,destroy}.yml`,
   `ansible-configure.yml`) and the two Justfiles' `list` recipes.
6. Apply order: `just deploy cloudflare zones/pavel-usanli.online/internal` → `just deploy proxmox <name>` →
   `just configure <name>`.
7. Update `README.md` services table.