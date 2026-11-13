# GitOps - homelab cluster

Flux CD watches this directory and reconciles the k3s cluster state continuously.

## Structure

```
gitops/clusters/homelab/
├── flux-system/          # Flux CD core components (auto-generated)
├── infrastructure/
│   ├── metallb/          # Bare-metal load balancer (IP pool: 192.168.1.120–130)
│   ├── metallb-config/   # IPAddressPool + L2Advertisement
│   ├── nfs-provisioner/  # StorageClass "nfs" backed by 192.168.1.108:/srv/nfs/k8s
│   ├── external-secrets/ # External Secrets Operator (syncs Vault → k8s secrets)
│   ├── external-secrets-config/  # ClusterSecretStore pointing at Vault
│   ├── traefik-config/   # Traefik ingress config, Cloudflare DNS-01 TLS, CrowdSec middleware
│   ├── crowdsec/         # CrowdSec IDS + AppSec engine + web UI
│   ├── sablier/          # Sablier scale-on-demand (starts workloads on request, idles after inactivity)
│   ├── trivy-operator/   # Container CVE scanning - reports surfaced in Headlamp
│   └── request-metrics/  # Vector: Traefik access log → per-source request counters for Prometheus
└── apps/
    ├── public/
    │   ├── personal-web-page/              # Personal website
    │   ├── mite-assistant-mcp/             # Mite time-tracking MCP server
    │   ├── capacity-planner/               # Capacity planner tool (Sablier scale-on-demand)
    │   ├── bunker-game-app/                # Bunker party game (Sablier scale-on-demand)
    │   ├── noco-google-connector-web-page/ # Noco Google connector web page (noco-google-connector.pavel-usanli.online)
    │   ├── proklinator/                    # proklinator.online — nginx placeholder
    │   └── workspaced-ai/                  # own namespace; web app at the root, API under /api/v1/ (ai.workspaced.online)
    └── private/
        ├── private-home-page/               # Internal services dashboard
        └── headlamp/                        # Kubernetes dashboard (+ Trivy plugin: CVE board)
```

## Required secrets in Vault

All secrets live under the `secret/` KV-v2 mount at `https://vault.internal.pavel-usanli.online:8200`.
External Secrets Operator syncs them into k8s secrets automatically.

### `secret/crowdsec-secrets`

| Property | Description |
|---|---|
| `bouncer-api-key` | Pre-shared key CrowdSec uses to authenticate the Traefik bouncer |
| `enrollment-key` | Enrollment key from [app.crowdsec.net](https://app.crowdsec.net) → Security Engines → Enroll |

```bash
# bouncer-api-key - random 32-byte hex string
openssl rand -hex 32

# enrollment-key - copy from app.crowdsec.net → Security Engines → + Add → Enroll command
# looks like: cscli console enroll <key>  ← the <key> part
```

Write to Vault:
```bash
vault kv put secret/crowdsec-secrets \
  bouncer-api-key="<value>" \
  enrollment-key="<value>"
```

### `secret/grafana-secrets`

| Property | Description |
|---|---|
| `admin-user` | Grafana admin login |
| `admin-password` | Grafana admin password |

Read by `ansible/proxmox/grafana-lxc` at configure time; the admin login applies only when
Grafana creates its database.

```bash
vault kv put secret/grafana-secrets \
  admin-user="admin" \
  admin-password="$(openssl rand -base64 24)"
```

### `secret/mite-assistant-mcp-secrets`

| Property | Description |
|---|---|
| `mite-url` | Mite API base URL |

```bash
# mite-url - your Mite account URL, e.g.:
echo "https://<account>.mite.de"

vault kv put secret/mite-assistant-mcp-secrets \
  mite-url="https://<account>.mite.de"
```

### `secret/songradar-secrets`

| Property | Description |
|---|---|
| `database-host` | PostgreSQL hostname used by SongRadar |
| `database-port` | PostgreSQL port |
| `database-name` | SongRadar database name |
| `database-username` | PostgreSQL username |
| `database-password` | PostgreSQL password |
| `audd-api-token` | Optional AudD token for automatic song recognition |

The optional AudD token is exposed to the app as `SONGRADAR_AUDD_API_TOKEN` by its
`ExternalSecret`.

### `secret/workspaced-secrets`

| Property | Description |
|---|---|
| `database-host` | PostgreSQL hostname used by the workspaced-ai API |
| `database-port` | PostgreSQL port |
| `database-name` | workspaced-ai database name |
| `database-username` | PostgreSQL username |
| `database-password` | PostgreSQL password |

Its `ExternalSecret` exposes each as `WORKSPACED_DB_*` to the API.

### Manual k8s secret - `cloudflare-api-token` (namespace: `kube-system`)

Used by Traefik for Cloudflare DNS-01 Let's Encrypt challenges. Created by the k3s Ansible playbook.

| Key | Description |
|---|---|
| `api-token` | Cloudflare API token with `Zone:DNS:Edit` permission |

Generate at [dash.cloudflare.com](https://dash.cloudflare.com) → My Profile → API Tokens → Create Token → **Edit zone DNS** template.

## Traefik request metrics

Traefik serves its own `/metrics` (status, method and latency per entryPoint, router and
service) at `traefik.internal.pavel-usanli.online/metrics`. Those carry no client address, so
`infrastructure/request-metrics/` runs Vector on every node, reads Traefik's access log and
exports `traefik_client_requests_total{client_ip,host,method,status,entrypoint}` on hostPort
9598. Prometheus scrapes both and keeps 30 days, which is what lets the nightly security agent
see a full day of sources after the log itself has rotated.

### Querying requests for a time range

Paste the setup block into bash or zsh, then any of the queries below. The range ends at
`END` and reaches back `RANGE`; both are plain strings, so no `date` call differs between
macOS and Linux. The blocks carry no comments because zsh does not treat `#` as one in an
interactive paste.

```bash
P=https://prometheus.internal.pavel-usanli.online:9090
END=2026-11-10T00:00:00Z
RANGE=24h
q() { curl -sG "$P/api/v1/query" --data-urlencode "query=$1" --data-urlencode "time=$END" | jq; }
r() { local m="traefik_client_requests_total$1"; echo "(($m - $m offset $RANGE >= 0) or $m)"; }
```

`r` counts each source's requests in the range, optionally narrowed by a label selector.
Never use `increase()` on this counter: a source's series starts at its first request, and
`increase()` drops everything before its second scrape, so a short scan reads as zero.

Every source, busiest first:

```bash
q "sort_desc(sum by (client_ip) ($(r)) > 0)"
```

What each source did:

```bash
q "sum by (client_ip, host, method, status) ($(r)) > 0"
```

Sources that got 4xx or 5xx:

```bash
q "sum by (client_ip) ($(r '{status=~"4..|5.."}')) > 0"
```

One source:

```bash
q "sum by (status, host) ($(r '{client_ip="203.0.113.7"}')) > 0"
```

Public against private:

```bash
q "sum by (entrypoint) ($(r))"
```

Hourly totals across the range, from Traefik's own counters (no client address). `START`
must be `END` minus `RANGE`:

```bash
START=2026-11-09T00:00:00Z
curl -sG "$P/api/v1/query_range" --data-urlencode 'query=sum by (entrypoint, code) (increase(traefik_entrypoint_requests_total[1h]))' --data-urlencode "start=$START" --data-urlencode "end=$END" --data-urlencode step=1h | jq
```

Keep `RANGE` under 48 hours and the range within the last 30 days: the exporter drops a
source after 48 idle hours, and Prometheus keeps 30 days. Counts are a lower bound across a
Vector restart. Paths and User-Agents are not in Prometheus; for those, read Traefik's log
while it lasts.

## How it works

```
Flux CD (polls GitHub every 1 min)
  └─ applies kustomizations in dependency order:
       flux-system → infrastructure → apps
```

- **External Secrets** pulls secrets from Vault into k8s `Secret` objects (refresh: 1 min)
- **MetalLB** assigns `192.168.1.120` to Traefik's `LoadBalancer` service
- **Traefik** terminates TLS via Cloudflare DNS-01, routes traffic to apps, runs CrowdSec middleware
- **CrowdSec** inspects requests via AppSec engine; decisions shared with Traefik bouncer
- **Trivy Operator** discovers every workload image and writes scan results as CRDs (see below)

## Container CVE scanning

`infrastructure/trivy-operator/` runs [Trivy Operator](https://aquasecurity.github.io/trivy-operator/). It discovers
images from the cluster itself — nothing here needs updating when an app is added under `apps/`.

Results are Kubernetes objects, one per workload:

```bash
kubectl get vulnerabilityreports -A          # CVEs per workload
kubectl get configauditreports -A            # misconfigurations
kubectl get exposedsecretreports -A          # secrets baked into images
kubectl get sbomreports -A                   # SBOM per workload
kubectl get clustercompliancereports         # k8s-cis-1.23
```

**The board** is the Trivy plugin in Headlamp at `headlamp.internal.pavel-usanli.online` → *Trivy* in the sidebar.
The plugin ships as an image; `apps/private/headlamp/deployment.yaml` has an initContainer that copies the bundle into
an emptyDir that Headlamp reads via `-plugins-dir`. Bumping the plugin means bumping that initContainer's image tag.

**Rescan cadence** is `operator.scannerReportTTL: 720h` (30 days), and it only applies to images that have not
changed. A new image tag changes the workload's pod-spec hash, which forces an immediate rescan regardless of the TTL —
so anything `gitops-bump-images` touches is rescanned on every bump, and the 30 days is the floor for images that sit
still. Force an immediate rescan of one workload by deleting its report:

```bash
kubectl delete vulnerabilityreport -n public <report-name>
```

**Ad-hoc scan of an arbitrary image** — reuses the in-cluster DB server, so there is no database download:

```bash
kubectl -n trivy-system run trivy-adhoc --rm -it --restart=Never \
  --image=mirror.gcr.io/aquasec/trivy:0.73.0 -- \
  image --server http://trivy-service.trivy-system:4954 <image-ref>
```

**Tuning knobs** in `helmrelease.yaml`: `trivy.severity` (currently `MEDIUM,HIGH,CRITICAL`), and
`trivy.ignoreUnfixed: true` if you want to hide CVEs with no upstream fix available.

> **Trap:** `operator.scanJobsConcurrentLimit` and `operator.scanJobTTL` are coupled. The operator counts scan jobs
> without filtering on status, so `Completed`/`Failed` jobs hold a slot until they are reaped. A small limit plus a long
> TTL stalls the sweep — symptom is a handful of reports, a few lingering `Complete` jobs, and an idle operator.
> `kubectl delete jobs -n trivy-system --all` unblocks it immediately.
