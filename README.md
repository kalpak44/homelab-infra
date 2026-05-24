# homelab-infra

Terraform (state in Cloudflare R2) + Ansible for a Proxmox homelab.
CI runs on a self-hosted runner on the Proxmox node — all deploys and destroys are triggered manually via GitHub Actions.

---

## Setup

### 1. Cloudflare R2 — create bucket and API token

1. In the Cloudflare dashboard → **R2** → **Create bucket**, name it (e.g. `homelab-terraform-state`)
2. Still in **R2**, click **Manage R2 API Tokens → Create Account API Token** (recommended — tied to the account, stays active permanently)
   - Permissions: **Object Read & Write**
   - Scope: the bucket you just created
3. After creation Cloudflare shows four values. You need only these two:

   | Shown on screen       | Save as                |
   |-----------------------|------------------------|
   | **Access Key ID**     | `R2_ACCESS_KEY_ID`     |
   | **Secret Access Key** | `R2_SECRET_ACCESS_KEY` |

   > Ignore **Token value** (Cloudflare API, not S3) and jurisdiction-specific endpoints unless your bucket is in a specific jurisdiction.

4. Copy the **S3 API** URL from the token page — looks like `https://<account-id>.r2.cloudflarestorage.com`. Save it as `R2_ENDPOINT`.

### 2. Proxmox — initial node setup

SSH into the node as root and run all commands below.

#### 2a. Create Terraform role and user

```bash
pveum role add Terraform \
  --privs "Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Allocate,Sys.Audit,Sys.Console,Sys.Modify,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.Cloudinit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.GuestAgent.Audit,VM.Migrate,VM.PowerMgmt,SDN.Use"

pveum user add terraform@pve --comment "Terraform automation"

# Grant role at root path (VMs, nodes)
pveum aclmod / --user terraform@pve --role Terraform

# Grant role on local storage (required for LXC template management)
pveum aclmod /storage/local --user terraform@pve --role Terraform

# Prints the token secret — copy it, shown only once
pveum user token add terraform@pve terraform --privsep 0
```

The username for Terraform is `terraform@pve!terraform`.

#### 2b. Enable snippet storage for cloud-init

```bash
pvesm set local --content images,rootdir,vztmpl,backup,snippets,iso
```

#### 2c. Create a runner VM and install the GitHub Actions agent

This VM is created **manually, once** — it lives on the LAN and has direct access to the Proxmox API, so port 8006 never needs to be exposed to the internet. All future Terraform runs happen through it.

First make sure you have an SSH public key on the Proxmox node to inject into the VM. If you don't have one yet:

```bash
# Check for existing keys
ls ~/.ssh/

# Generate one if needed
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

Or copy your local machine's public key to the node:

```bash
# Run this on your local machine
ssh-copy-id root@<proxmox-ip>
# Then on Proxmox the key will be in ~/.ssh/authorized_keys
```

Create the runner VM directly from the Ubuntu cloud image:

```bash
RUNNER_ID=101
STORAGE=local-lvm
IMAGE=/tmp/ubuntu-2404.img

wget -q -O $IMAGE https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

qm create $RUNNER_ID \
  --name github-runner \
  --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26

qm importdisk $RUNNER_ID $IMAGE $STORAGE
qm set $RUNNER_ID \
  --scsihw virtio-scsi-pci \
  --scsi0 $STORAGE:vm-$RUNNER_ID-disk-0 \
  --ide2 $STORAGE:cloudinit \
  --boot order=scsi0 \
  --serial0 socket --vga serial0 \
  --ipconfig0 ip=192.168.1.101/24,gw=192.168.1.1 \
  --sshkeys ~/.ssh/id_ed25519.pub \
  --ciuser ubuntu
qm resize $RUNNER_ID scsi0 +10G
qm start $RUNNER_ID
```

SSH into the VM once it boots, then install the required tooling:

```bash
ssh ubuntu@192.168.1.101

# Install deps first
sudo apt-get update && sudo apt-get install -y ansible python3-pip git curl unzip

# Terraform
wget -q -O /tmp/tf.zip https://releases.hashicorp.com/terraform/1.15.4/terraform_1.15.4_linux_amd64.zip
unzip /tmp/tf.zip terraform -d /tmp
sudo mv /tmp/terraform /usr/local/bin/terraform
```

Register the GitHub Actions runner. Go to the repo → **Settings → Actions → Runners → New self-hosted runner**, select **Linux x64**, and copy the token GitHub shows. Then on the VM:

```bash
mkdir actions-runner && cd actions-runner

# Download
curl -o actions-runner-linux-x64-2.334.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.334.0/actions-runner-linux-x64-2.334.0.tar.gz

# Validate
echo "048024cd2c848eb6f14d5646d56c13a4def2ae7ee3ad12122bee960c56f3d271  actions-runner-linux-x64-2.334.0.tar.gz" | shasum -a 256 -c

# Extract
tar xzf ./actions-runner-linux-x64-2.334.0.tar.gz

# Configure — paste your token from GitHub
./config.sh --url https://github.com/<owner>/homelab-infra --token <TOKEN>

# Test it runs (foreground, Ctrl+C to stop)
./run.sh
```

Once confirmed working, install as a systemd service so it survives reboots:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

Enable the VM to start automatically when the Proxmox host reboots (run on the Proxmox node):

```bash
qm set 101 --onboot 1
```

#### Updating the runner

The runner agent **auto-updates itself** when GitHub requires a newer version — no action needed for agent updates.

For OS-level updates (security patches):

```bash
ssh ubuntu@192.168.1.101
sudo apt update && sudo apt upgrade -y
```

For a full VM rebuild (e.g. major OS version):

```bash
ssh ubuntu@192.168.1.101
cd actions-runner

# Stop and unregister the old runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall
./config.sh remove --token <TOKEN>   # token from Settings → Actions → Runners → remove
```

Then destroy the VM, create a new one from the runner setup steps above, and re-register with GitHub.

### 3. GitHub — add repository secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret                    | Where to get it                                                              |
|---------------------------|------------------------------------------------------------------------------|
| `R2_ENDPOINT`             | S3 API URL from the R2 token page, e.g. `https://<id>.r2.cloudflarestorage.com` |
| `R2_BUCKET_NAME`          | Bucket name you created, e.g. `homelab-terraform-state`                      |
| `R2_ACCESS_KEY_ID`        | Access Key ID from the R2 token page                                         |
| `R2_SECRET_ACCESS_KEY`    | Secret Access Key from the R2 token page                                     |
| `PROXMOX_ENDPOINT`        | `https://<proxmox-ip>:8006`                                                  |
| `PROXMOX_USERNAME`        | `terraform@pve!terraform`                                                    |
| `PROXMOX_PASSWORD`        | Proxmox API token secret from step 2a                                        |
| `SSH_PUBLIC_KEY`          | Contents of `~/.ssh/id_ed25519.pub` on the Proxmox node                      |
| `SSH_PRIVATE_KEY`         | Contents of `~/.ssh/id_ed25519` on the Proxmox node (used by Ansible)        |
| `LETSENCRYPT_EMAIL`        | Email address for Let's Encrypt account registration                         |
| `ADGUARD_USERNAME`        | AdGuard admin username of your choice                                         |
| `ADGUARD_PASSWORD`        | AdGuard admin password of your choice                                         |
| `VAULT_USERNAME`          | Vault admin username — alphanumeric only, no `@` or special chars            |
| `VAULT_PASSWORD`          | Vault admin password of your choice                                           |
| `POSTGRESQL_DB`           | PostgreSQL database name to create                                            |
| `POSTGRESQL_USER`         | PostgreSQL application user to create                                         |
| `POSTGRESQL_PASSWORD`     | PostgreSQL application user password                                          |
| `PGADMIN_EMAIL`           | pgAdmin admin login email of your choice                                      |
| `PGADMIN_PASSWORD`        | pgAdmin admin password of your choice                                         |
| `REDIS_PASSWORD`          | Redis auth password                                                           |
| `REDIS_COMMANDER_USER`    | Redis Commander web UI username                                               |
| `REDIS_COMMANDER_PASSWORD`| Redis Commander web UI password                                               |
| `PORTAINER_ADMIN_USERNAME`| Portainer admin username — suggested: `admin`                                 |
| `PORTAINER_ADMIN_PASSWORD`| Portainer admin password — **minimum 12 characters** (Portainer requirement)  |
| `HAPROXY_STATS_USER`      | HAProxy stats page username of your choice                                    |
| `HAPROXY_STATS_PASSWORD`  | HAProxy stats page password of your choice                                    |
| `CLOUDFLARE_API_TOKEN`    | Cloudflare API token with `Zone:DNS:Edit` permission for `pavel-usanli.online` — used by Terraform to manage DNS records and by cert-manager for Let's Encrypt DNS-01 |
| `FLUX_GITHUB_TOKEN`       | GitHub PAT with `repo` scope — used by Flux CD to read/write this repository during bootstrap |
| `HAPROXY_PUBLIC_IP`       | Public WAN IP of your router/HAProxy — used by Terraform to register public-facing `A` records in Cloudflare (apex, www, mite-assistant) |

### 4. Proxmox — TLS certificate via Let's Encrypt

The default Proxmox cert is signed by its own internal CA, which browsers don't trust. Replace it with a Let's Encrypt cert using the Cloudflare DNS-01 challenge — no need to expose port 80.

**Get a Cloudflare API token** — My Profile → API Tokens → Create Token → Edit zone DNS → scope to `your-domain.com`. Copy the token.

The Proxmox web UI is available at `https://192.168.1.50:8006` or `https://proxmox.internal.pavel-usanli.online:8006`.

**Run on the Proxmox node:**

```bash
# Register a Let's Encrypt account (once)
pvenode acme account register default your@email.com \
  --directory https://acme-v02.api.letsencrypt.org/directory

# Add Cloudflare DNS plugin (--data expects a file, not inline value)
echo "CF_Token=<cloudflare-api-token>" > /tmp/cf.env
pvenode acme plugin add dns cloudflare --api cf --data /tmp/cf.env
rm /tmp/cf.env

# Set the domain on this node
pvenode config set \
  --acme account=default \
  --acmedomain0 domain=<proxmox-hostname>.<your-domain>,plugin=cloudflare

# Issue the certificate (~30 seconds)
pvenode acme cert order
```

Proxmox renews the certificate automatically via a built-in systemd timer — nothing else is needed.

### 5. GitHub — create environments

Go to **Settings → Environments** and create two environments: `common` and `prod`.

Add a required reviewer to `prod` to require manual approval before running prod deploys.

---

## Services

### AdGuard Home

DNS ad-blocker running in an LXC container (`common` env, `192.168.1.2`).

**Secrets required:** `ADGUARD_USERNAME`, `ADGUARD_PASSWORD`

**Deploy:** Run **Deploy** → `adguard`

AdGuard Home is available at `https://adguard.internal.pavel-usanli.online` (or `http://192.168.1.2` before TLS is provisioned). SSH is enabled on port 22 with key-only auth. A Let's Encrypt certificate is issued automatically via Cloudflare DNS-01 challenge and renewed by certbot's systemd timer.

**Point your router's DNS to `192.168.1.2`** (or set it per-device) to start filtering.

**To update AdGuard version** — bump `adguard_version` in `ansible/roles/adguard/defaults/main.yml` and re-run the deploy.

### HashiCorp Vault

Secret manager running in an LXC container (`common` env, `192.168.1.3`).

**Secrets required:** `VAULT_USERNAME`, `VAULT_PASSWORD`

**Deploy:** Run **Deploy** → `vault`

The playbook initialises Vault (if not already done), unseals it, enables userpass auth, and creates the admin user. Vault is available at `http://192.168.1.3:8200` or `http://vault.internal.pavel-usanli.online:8200`.

> The unseal key and root token are saved to `/root/vault-init.json` on the container — back this file up somewhere safe.

**To update Vault version** — bump `vault_version` in `ansible/roles/vault/defaults/main.yml` and re-run the deploy.

### PostgreSQL

Database server running in an LXC container (`common` env, `192.168.1.4`).

**Secrets required:** `POSTGRESQL_DB`, `POSTGRESQL_USER`, `POSTGRESQL_PASSWORD`

**Deploy:** Run **Deploy** → `postgres`

PostgreSQL 16 listens on `192.168.1.4:5432` (also reachable as `postgres.internal.pavel-usanli.online:5432`). The application user and database are created automatically. All hosts on `192.168.1.0/24` can connect using password auth (scram-sha-256).

### pgAdmin

Web-based PostgreSQL management UI running on the same LXC container as PostgreSQL (`common` env, `192.168.1.4`).

**Secrets required:** `PGADMIN_EMAIL`, `PGADMIN_PASSWORD`

**Deploy:** Run **Deploy** → `postgres`

pgAdmin is available at `https://pgadmin.internal.pavel-usanli.online` (or `http://192.168.1.4` before TLS is provisioned — HTTP redirects to HTTPS once deployed). A Let's Encrypt certificate is issued automatically via Cloudflare DNS-01 challenge. To connect to PostgreSQL, add a new server in the UI:
- **Host:** `192.168.1.4`
- **Port:** `5432`
- **Username / Password:** the `POSTGRESQL_USER` / `POSTGRESQL_PASSWORD` secrets above

### Redis

Redis + Redis Commander web UI running in a single LXC container (`common` env, `192.168.1.6`).

**Secrets required:** `REDIS_PASSWORD`, `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD`

**Deploy:** Run **Deploy** → `redis`

Redis listens on `192.168.1.6:6379` or `redis.internal.pavel-usanli.online:6379` (password-protected). Redis Commander is available at `http://192.168.1.6:8081` or `http://redis.internal.pavel-usanli.online:8081`.

### Portainer

Docker management UI running in a VM (`common` env, `192.168.1.7`).

**Secrets required:** `PORTAINER_ADMIN_USERNAME`, `PORTAINER_ADMIN_PASSWORD`

**Deploy:** Run **Deploy** → `portainer`

Portainer CE runs as a Docker container inside the VM. nginx listens on port 80 and 443 — HTTP requests are force-redirected to HTTPS. A Let's Encrypt certificate is issued automatically via Cloudflare DNS-01 challenge and renewed by certbot's systemd timer.

Portainer is available at `https://portainer.internal.pavel-usanli.online` (or `http://192.168.1.7` before TLS is provisioned). The admin account is initialised automatically on first deploy. SSH is enabled on port 22 with key-only auth.

### HAProxy (prod load balancer)

External load balancer for the k3s cluster, running in an LXC container (`prod` env, `192.168.1.109`).

**Secrets required:** `HAPROXY_STATS_USER`, `HAPROXY_STATS_PASSWORD`

**Deploy:** Run **Deploy** → `haproxy`

HAProxy stats are available at `http://192.168.1.109:8404/stats`. Traffic flow:
- `:80` — HTTP forwarded to Traefik at `192.168.1.120:80`
- `:443` — TCP passthrough to Traefik at `192.168.1.120:443` (TLS terminated by Traefik)

### Kubernetes cluster (prod)

k3s two-node cluster with an external HAProxy load balancer and NFS storage, all in the `prod` env.

| Host | Type | IP | Spec | Role |
|---|---|---|---|---|
| `k3s-1` | VM | 192.168.1.110 | 4 CPU / 8 GB / 40 GB | k3s control plane |
| `k3s-2` | VM | 192.168.1.111 | 4 CPU / 8 GB / 40 GB | k3s worker |
| `haproxy` | LXC | 192.168.1.109 | 1 CPU / 512 MB / 8 GB | HAProxy — external load balancer |
| `nfs` | VM | 192.168.1.108 | 2 CPU / 2 GB / 20 GB OS + 512 GB data | NFS server — persistent volume storage |
| MetalLB pool | — | 192.168.1.120–130 | — | Virtual IPs for LoadBalancer services |

**Traffic flow:**
```
Internet → HAProxy (192.168.1.109) → MetalLB IP (192.168.1.120) → Traefik → apps
```

**In-cluster components** (deployed via Flux CD, watching `gitops/clusters/homelab/`):
- **MetalLB** — assigns IPs from the `192.168.1.120–130` pool to LoadBalancer services
- **Traefik** — ingress controller at `192.168.1.120`, TLS via Cloudflare DNS-01 Let's Encrypt — [`https://traefik.internal.pavel-usanli.online`](https://traefik.internal.pavel-usanli.online)
- **NFS provisioner** — StorageClass `nfs` backed by `192.168.1.108:/srv/nfs/k8s`
- **Flux CD** — GitOps operator
- **External Secrets Operator** — syncs secrets from Vault (`192.168.1.3`) into k8s secrets
- **CrowdSec** — intrusion detection + bouncer for Traefik — UI at [`https://crowdsec.internal.pavel-usanli.online`](https://crowdsec.internal.pavel-usanli.online)

**Apps:**
- **Private home page** — internal dashboard — [`https://home.internal.pavel-usanli.online`](https://home.internal.pavel-usanli.online)

**Deploy:**

1. Run **Deploy** → `haproxy` (creates LXC + configures HAProxy)
2. Run **Deploy** → `nfs` (creates VM + configures NFS)
3. Run **Deploy** → `k3s` (creates VMs + installs k3s)
4. Run **Deploy** → `k3s/flux` (bootstraps Flux CD + deploys all in-cluster components)

**kubectl access from your local machine** (on the `192.168.1.0/24` network):

```bash
# Copy kubeconfig from the control plane node
scp ubuntu@192.168.1.110:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab.yaml

# Point it at the node's LAN IP (k3s defaults to 127.0.0.1)
sed -i '' 's/127.0.0.1/192.168.1.110/' ~/.kube/homelab.yaml

# Use it
export KUBECONFIG=~/.kube/homelab.yaml
kubectl get nodes
```

---

## CI behaviour

| Event           | Workflow       | What it does                                       |
|-----------------|----------------|----------------------------------------------------|
| Manual dispatch | `deploy.yml`   | Terraform apply + Ansible for the selected service |
| Manual dispatch | `destroy.yml`  | Terraform destroy for the selected service         |

### Deploy options

| Option | Terraform | Ansible playbooks |
|---|---|---|
| `all` | apply everything | adguard → vault → postgres → redis → portainer → haproxy → nfs → k3s |
| `proxmox-dns` | apply everything | skipped |
| `adguard` | apply everything | adguard |
| `vault` | apply everything | vault |
| `postgres` | apply everything | postgres |
| `redis` | apply everything | redis |
| `portainer` | apply everything | portainer |
| `haproxy` | apply everything | haproxy |
| `nfs` | apply everything | nfs |
| `k3s` | apply everything | k3s |
| `k3s/flux` | skipped | flux |
| `k3s/flux/personal-web-page` | `cloudflare_record.personal_web_page_apex` + `www` (requires `HAPROXY_PUBLIC_IP`) | skipped |
| `k3s/flux/private-home-page` | `cloudflare_record.private_home_page` | skipped |
| `k3s/flux/mite-assistant-mcp` | `cloudflare_record.mite_assistant` (requires `HAPROXY_PUBLIC_IP`) | skipped |

> Ansible always uses the single `inventories/homelab.yml` inventory.
> `k3s/flux/*` options run a targeted Terraform apply for the app's Cloudflare DNS record only — no Ansible step.

### Destroy options

| Option | Terraform targets |
|---|---|
| `all` | entire state |
| `proxmox-dns` | `cloudflare_record.proxmox` |
| `adguard` | `module.adguard` |
| `vault` | `module.vault` |
| `postgres` | `module.postgres` |
| `redis` | `module.redis` |
| `portainer` | `module.portainer` |
| `haproxy` | `module.haproxy` |
| `nfs` | `module.nfs` |
| `k3s` | `module.k3s` |

---

## Local init (one-time)

```bash
export AWS_ACCESS_KEY_ID=<R2_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<R2_SECRET_ACCESS_KEY>
export AWS_ENDPOINT_URL_S3=<R2_ENDPOINT>

cd terraform
terraform init -backend-config="bucket=<R2_BUCKET_NAME>"
```