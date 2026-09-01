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
│   └── trivy-operator/   # Container CVE scanning - reports surfaced in Headlamp
└── apps/
    ├── public/
    │   ├── personal-web-page/     # Personal website
    │   ├── mite-assistant-mcp/    # Mite time-tracking MCP server
    │   ├── capacity-planner/      # Capacity planner tool (Sablier scale-on-demand)
    │   ├── shopify-gpt-assistant/ # Shopify GPT assistant
    │   ├── bunker-game-app/       # Bunker party game (Sablier scale-on-demand)
    │   ├── google-assistant-mcp/  # Google MCP server
    │   ├── nocobase/              # NocoBase no-code platform
    │   ├── plugin-noco-tools/     # Noco Tools landing page (noco-ai-tools.pavel-usanli.online)
    │   └── proklinator/           # proklinator.online — nginx placeholder
    └── private/
        ├── private-home-page/               # Internal services dashboard
        ├── headlamp/                        # Kubernetes dashboard (+ Trivy plugin: CVE board)
        ├── crowdsec-web-ui/                 # CrowdSec web UI (private access)
        ├── lex-bg-connector/                # Lex background connector (data preloader)
        ├── playwright-mcp/                  # Microsoft Playwright MCP (browser automation; NFS profile, DuckDuckBot UA)
        └── ciela-mcp/                       # Ciela MCP server (Bulgarian legislation search)
```

## Required secrets in Vault

All secrets live under the `secret/` KV-v2 mount at `https://vault.internal.pavel-usanli.online:8200`.
External Secrets Operator syncs them into k8s secrets automatically.

### `secret/crowdsec-secrets`

| Property | Description |
|---|---|
| `bouncer-api-key` | Pre-shared key CrowdSec uses to authenticate the Traefik bouncer |
| `webui-machine-id` | Machine ID (username) for the CrowdSec web UI |
| `webui-password` | Password for the CrowdSec web UI |
| `enrollment-key` | Enrollment key from [app.crowdsec.net](https://app.crowdsec.net) → Security Engines → Enroll |

```bash
# bouncer-api-key - random 32-byte hex string
openssl rand -hex 32

# webui-machine-id - pick any short alphanumeric name, e.g.:
echo "homelab"

# webui-password - random password
openssl rand -base64 24

# enrollment-key - copy from app.crowdsec.net → Security Engines → + Add → Enroll command
# looks like: cscli console enroll <key>  ← the <key> part
```

Write to Vault:
```bash
vault kv put secret/crowdsec-secrets \
  bouncer-api-key="<value>" \
  webui-machine-id="<value>" \
  webui-password="<value>" \
  enrollment-key="<value>"
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

### `secret/ciela-secrets`

| Property | Description |
|---|---|
| `username` | Ciela (web7.ciela.net) account username |
| `password` | Ciela account password |

```bash
vault kv put secret/ciela-secrets \
  username="<username>" \
  password="<password>"
```

### `secret/nocobase-secrets`

| Property | Description |
|---|---|
| `db-user` | PostgreSQL username |
| `db-password` | PostgreSQL password |
| `app-key` | Secret key used to encrypt user tokens (generate once, never rotate) |

```bash
vault kv put secret/nocobase-secrets \
  db-user="<db-user>" \
  db-password="<db-password>" \
  app-key="$(openssl rand -hex 32)"
```

### `secret/shopify-gpt-assistant-secrets`

| Property | Description |
|---|---|
| `api-key` | Shopify app API key |
| `api-secret` | Shopify app API secret |
| `database-url` | Database connection string used by the app |

```bash
vault kv put secret/shopify-gpt-assistant-secrets \
  api-key="<shopify-api-key>" \
  api-secret="<shopify-api-secret>" \
  database-url="<database-url>"
```

### Manual k8s secret - `cloudflare-api-token` (namespace: `kube-system`)

Used by Traefik for Cloudflare DNS-01 Let's Encrypt challenges. Created by the k3s Ansible playbook.

| Key | Description |
|---|---|
| `api-token` | Cloudflare API token with `Zone:DNS:Edit` permission |

Generate at [dash.cloudflare.com](https://dash.cloudflare.com) → My Profile → API Tokens → Create Token → **Edit zone DNS** template.

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
