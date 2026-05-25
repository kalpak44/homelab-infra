# GitOps — homelab cluster

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
│   └── crowdsec/         # CrowdSec IDS + AppSec engine + web UI
└── apps/
    ├── public/
    │   ├── personal-web-page/     # Personal website
    │   └── mite-assistant-mcp/    # Mite time-tracking MCP server
    └── private/
        ├── private-home-page/     # Internal services dashboard
        ├── headlamp/              # Kubernetes dashboard
        └── crowdsec-web-ui/       # CrowdSec web UI (private access)
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
# bouncer-api-key — random 32-byte hex string
openssl rand -hex 32

# webui-machine-id — pick any short alphanumeric name, e.g.:
echo "homelab"

# webui-password — random password
openssl rand -base64 24

# enrollment-key — copy from app.crowdsec.net → Security Engines → + Add → Enroll command
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
# mite-url — your Mite account URL, e.g.:
echo "https://<account>.mite.de"

vault kv put secret/mite-assistant-mcp-secrets \
  mite-url="https://<account>.mite.de"
```

### Manual k8s secret — `cloudflare-api-token` (namespace: `kube-system`)

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
