# 10. Service catalog

Reference addresses, resource locations and service-specific notes. Follow the
[numbered build guide](<0 - Prerequisites.md#build-order>) for installation order.
Commands in this reference run from the repository root unless stated otherwise.

## Services

All services live behind `*.internal.pavel-usanli.online` (LAN only, unproxied) or `*.pavel-usanli.online` (public,
routed through a Cloudflare Zero Trust tunnel — no open WAN ports required). `proklinator.online` and `workspaced.online` are
further public zones on the same tunnel, managed from the same `cloudflare/tunnels/homelab` dir — registered at GoDaddy, nameservers
delegated to Cloudflare. Deploy order: Terraform (creates the box + DNS record) → Ansible (configures the service).

| Service                    | Where      | IP            | Terraform dir                          | Ansible dir                                 |
|----------------------------|------------|---------------|----------------------------------------|---------------------------------------------|
| AdGuard Home               | LXC        | 192.168.1.2   | `proxmox/adguard-lxc`                  | `01-networking/adguard-lxc`                       |
| Vault                      | LXC        | 192.168.1.3   | `proxmox/vault-lxc`                    | `03-vault/vault-lxc`                         |
| PostgreSQL + pgAdmin       | LXC        | 192.168.1.4   | `proxmox/postgres-lxc`                 | `05-services/postgres-lxc`                      |
| Redis + Commander          | LXC        | 192.168.1.6   | `proxmox/redis-lxc`                    | `05-services/redis-lxc`                         |
| Portainer                  | VM         | 192.168.1.7   | `proxmox/portainer-vm`                 | `05-services/portainer-vm`                      |
| NocoBase                   | LXC        | 192.168.1.5   | `proxmox/nocobase-lxc`                 | `05-services/nocobase-lxc` |
| Mihal (WARP-only SSH)      | LXC | 192.168.1.9 | `proxmox/mihal-lxc` | `05-services/mihal-lxc` |
| Cloudflare Tunnel          | LXC        | 192.168.1.10  | `proxmox/cloudflared-lxc`              | `05-services/cloudflared-lxc`                   |
| Prometheus                 | LXC        | 192.168.1.11  | `proxmox/prometheus-lxc`               | `05-services/prometheus-lxc`                    |
| Grafana                    | LXC        | 192.168.1.12  | `proxmox/grafana-lxc`                  | `05-services/grafana-lxc`                       |
| RustFS (S3)                | LXC        | 192.168.1.13  | `proxmox/rustfs-lxc`                   | `05-services/rustfs-lxc`                        |
| NFS server (k3s PVs)       | VM         | 192.168.1.108 | `proxmox/nfs-vm`                       | `02-platform/nfs-vm`                            |
| k3s control plane          | VM         | 192.168.1.110 | `proxmox/k3s-cluster`                  | `02-platform/k3s-cluster` (`cluster-setup.yml`) |
| k3s worker                 | VM         | 192.168.1.111 | `proxmox/k3s-cluster`                  | (same)                                      |
| GitHub runner (optional)   | VM | 192.168.1.101 | — (bootstrap) | `80-runner/` |
| Flux CD bootstrap          | -          | (on k3s)      | -                                      | `04-gitops/flux/playbook.yml` |
| Cloudflare Tunnel (k3s)    | Cloudflare | -             | `cloudflare/tunnels/homelab`           | -                                           |
| Cloudflare Tunnel (mihal)  | Cloudflare | -             | `cloudflare/tunnels/mihal`             | -                                           |
| `*.internal` DNS records   | Cloudflare | -             | `cloudflare/zones/pavel-usanli.online/internal` | -                                  |
| Email (routing + Mailjet)  | Cloudflare | -             | `cloudflare/zones/pavel-usanli.online/email` | -                                     |
| Email (forwarding + Mailjet sending) | Cloudflare | -             | `cloudflare/zones/workspaced.online/email` | -                                       |
| Edge (WAF, redirects)      | Cloudflare | -             | `cloudflare/zones/<zone>/edge`         | -                                           |

### Per-service notes

**AdGuard Home** – Point your router's DNS to `192.168.1.2` (or set it per-device). UI at
`https://adguard.internal.pavel-usanli.online`. To bump versions edit
`ansible/01-networking/adguard-lxc/roles/adguard/defaults/main.yml`.

**Vault** - Playbook initializes, unseals, enables userpass auth, and creates the admin. Unseal key and root token are
saved to `/root/vault-init.json` inside the container - **back this file up**. UI at
`https://vault.internal.pavel-usanli.online:8200`. A systemd override
(`/etc/systemd/system/vault.service.d/override.conf`) auto-unseals Vault after every `vault.service` restart
(e.g. the certbot TLS-renewal hook, or a container/host reboot) using the key from `/root/vault-init.json`, so it no
longer needs a manual unsealing via the UI each time.

**PostgreSQL + pgAdmin** - Both roles run in a single `just configure postgres-lxc`. Postgres listens on
`192.168.1.4:5432`; pgAdmin at `https://pgadmin.internal.pavel-usanli.online`. All hosts on `192.168.1.0/24` connect
with password auth (scram-sha-256).

**Redis** – Redis on `192.168.1.6:6379`, Commander UI at `http://redis.internal.pavel-usanli.online:8081`.
Installed from `packages.redis.io`, not Ubuntu universe, which never moves off 7.0.15; `just configure
redis-lxc` upgrades to the newest upstream release on every run.

**Prometheus** – UI and API at `https://prometheus.internal.pavel-usanli.online:9090`, served with a Let's Encrypt
certificate issued by certbot over DNS-01. The TSDB lives on a dedicated 20G volume at `/var/lib/prometheus`, capped at
30 days or 15GB, whichever comes first. It scrapes itself and a loopback-bound `node_exporter`; add a target by
appending to `prometheus_extra_scrape_jobs` in
`ansible/05-services/prometheus-lxc/roles/prometheus/defaults/main.yml`. A loopback-bound `blackbox_exporter` probes
each entry in `prometheus_probes` in that file (HTTPS with certificate checks, DNS), and Grafana's **Service health**
dashboard draws one timeline per service. All three binaries come from upstream tarballs — Ubuntu noble's `prometheus`
package is a 2.x that never moves — so bumping a version is editing that same file.

**Grafana** – `https://grafana.internal.pavel-usanli.online`, on 443 with a certbot certificate. The Prometheus
datasource and the alert rules are provisioned from `ansible/05-services/grafana-lxc/roles/grafana/`. Dashboards are built
in the UI, or kept as JSON in that role's `files/`, which `ansible/05-services/grafana-lxc/generate-dashboards.py`
writes — edit the script, never the JSON. Every inventory host gets its own board in the Hosts folder, and
*Homelab hosts* links to each. The admin login is read from Vault
(`secret/grafana-secrets`) at configure time, so the role needs no CI secret of its own.

**RustFS** – S3 API at `https://rustfs.internal.pavel-usanli.online`, console at `:9001`, both on a certbot
certificate. Objects live on a 100G volume at `/data`. The root keys are read from Vault (`secret/rustfs-secrets`,
`access-key` and `secret-key`) at configure time.

**NocoBase** – LAN-isolated: the Proxmox firewall drops all outbound traffic to `192.168.0.0/16` on the
container's veth, except PostgreSQL (`192.168.1.4:5432`) and Redis (`192.168.1.6:6379`). Internet access and
inbound LAN access are unaffected. This is the only consumer of the cluster-wide firewall switch, which is
declared in `terraform/proxmox/nocobase-lxc/` with ACCEPT policies — a second isolated guest must not redeclare it.

Terraform generates a dedicated ED25519 keypair on first apply and writes it to the gitignored
`terraform/proxmox/nocobase-lxc/.ssh/`. If the local key files are missing,
recover them with `just output proxmox nocobase-lxc ssh_private_key` — the state on R2 is the copy of record.
`just configure nocobase-lxc` then hardens sshd: **port 22022**, key-only, `PermitRootLogin prohibit-password`.
It deliberately skips `_shared/enable-root-ssh.yml`, which would otherwise force `PasswordAuthentication yes` back
on, and it disables `ssh.socket` — Ubuntu 24.04 socket-activates sshd, which makes the `Port` directive a silent
no-op until systemd hands the port back. Root keeps its password for `pct enter 207` from the node as break-glass.

The same run installs an nftables ruleset: inbound on the container's `eth0` is default-deny, with **80, 443 and SSH
(22022) open** and nothing else — notably not NocoBase's own `0.0.0.0:13000`, which every LAN and WARP client could
reach before. `nocobase_firewall_admin_cidr` narrows SSH to one source range if wanted; it is empty by default,
because what guards that port is key-only sshd, and no WAN port-forward routes to it in the first place. It filters
in the `prerouting` hook at priority
`mangle` — after conntrack, before NAT — so a Docker-published port cannot slip past it the way it would past an
`input`-hook ruleset, and so `ct state` still works. Only this table is replaced on apply, never `flush ruleset`,
which would take Docker's own tables with it. Egress policy stays where it was, on the Proxmox veth firewall.

Cloudflare's edge is the other half, and the origin cannot reach it: a proxied hostname is also served on 8080, 8880,
2052, 2082, 2086, 2095 (HTTP) and 2053, 2083, 2087, 2096, 8443 (HTTPS), and the tunnel forwards all of them to the
same `http://192.168.1.5:80` — so `ownai.deepcraftstudio.com:8080` was this box's port 80, not a service on 8080.
`zones/pavel-usanli.online/edge/edge-ports.tf` blocks anything the edge did not accept on 80 or 443. It needs **Zone:WAF:Edit** on
`CLOUDFLARE_API_TOKEN`, which the current token does not have.

**Portainer** - Docker + nginx + certbot inside the VM. UI at `https://portainer.internal.pavel-usanli.online`. First
visit shows a setup wizard – create the admin there within 5 minutes of the first launch (
`sudo docker restart portainer` to re-open if it times out).

**k3s cluster** - Two-node cluster (control plane + worker). `just configure k3s-cluster` runs the 3-phase bootstrap (
prep nodes → install server on k3s-1 → join k3s-2). Then `just configure k3s-cluster/flux` installs Flux CD, which
reconciles everything under `gitops/clusters/homelab/`.

To use `kubectl` locally on the `192.168.1.0/24` network:

```bash
mkdir -p ~/.kube
(umask 077; ssh root@192.168.1.110 'cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/homelab.yaml)
chmod 600 ~/.kube/homelab.yaml
sed -i '' 's/127.0.0.1/192.168.1.110/' ~/.kube/homelab.yaml
export KUBECONFIG=~/.kube/homelab.yaml
kubectl get nodes
```

**Cloudflare Tunnel** – `cloudflared` daemon running on LXC 210 (`192.168.1.10`). Connects outbound to the
Cloudflare Zero Trust network; all public traffic for `*.pavel-usanli.online` routes through the tunnel to Traefik
at `192.168.1.120` — no open WAN ports needed. The tunnel is provisioned by `cloudflare/tunnels/homelab`
(outputs `tunnel_token`); the daemon is installed and configured by `ansible/05-services/cloudflared-lxc`.
Firewall: outbound restricted to `192.168.1.120` (k3s) + internet only.

To retrieve the tunnel token after deploying `cloudflare/tunnels/homelab`:

```bash
cd terraform && just output cloudflare tunnels/homelab tunnel_token
```

Save the printed value as `CLOUDFLARE_TUNNEL_TOKEN` in the ignored root `.env`.
Then configure the daemon:

```bash
cd ansible && just configure cloudflared-lxc
```

**Email** - inbound goes through Cloudflare Email Routing, one `zones/<zone>/email` dir per domain:
`contact@pavel-usanli.online`, `contact@`, `sales@`, `support@` and `investor@workspaced.online`, and `sales@proklinator.online` all forward to Gmail. The first forwarding address on
the account triggers a verification email from Cloudflare; later zones reuse it.

Outbound from `contact@…` goes through Mailjet, whose senders, SPF, DKIM and DMARC records are all in
`zones/pavel-usanli.online/email` (`MJ_APIKEY_PUBLIC`/`MJ_APIKEY_PRIVATE`). The one manual step is Gmail's side:
**Gmail → Settings → Accounts → Send mail as → Add**, backed by Mailjet SMTP (`in-v3.mailjet.com:587`, TLS). DMARC
is `p=none`; tighten it to `p=quarantine` in `dmarc.tf` once the reports show every sender passing SPF/DKIM.

---

## In-cluster services (Flux CD)

Not managed by Terraform or Ansible – Flux reconciles these from `gitops/clusters/homelab/`. See [
`gitops/README.md`](../gitops/README.md) for the full list.

Highlights:

- **MetalLB** - LoadBalancer IP pool `192.168.1.120–130`
- **Traefik** - ingress at `192.168.1.120`, TLS via Cloudflare DNS-01
- **cert-manager** - issues Let's Encrypt certs
- **External Secrets Operator** - syncs Vault → k8s secrets
- **CrowdSec** - IDS/IPS + AppSec middleware
- **NFS provisioner** - StorageClass `nfs` backed by `192.168.1.108:/srv/nfs/k8s`
- **Trivy Operator** - container CVE / misconfig / SBOM scanning, board via the Trivy plugin in Headlamp

---
