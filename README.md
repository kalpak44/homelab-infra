# homelab-infra

Terraform (state in Cloudflare R2) + Ansible for a Proxmox homelab.
CI runs on a self-hosted runner on the Proxmox node — plan on PRs, apply on merge to `main`.

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
  --privs "Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Allocate,Sys.Audit,Sys.Console,Sys.Modify,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.Cloudinit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Migrate,VM.PowerMgmt,SDN.Use"

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

#### 2c. Create a cloud-init VM template

```bash
VM_ID=9000
STORAGE=local-lvm   # adjust to your datastore
IMAGE=/tmp/ubuntu-2404.img

wget -q -O $IMAGE https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

qm create $VM_ID \
  --name ubuntu-2404-template \
  --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26

qm importdisk $VM_ID $IMAGE $STORAGE
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-0
qm set $VM_ID --ide2 $STORAGE:cloudinit
qm set $VM_ID --boot order=scsi0 --serial0 socket --vga serial0
qm template $VM_ID
```

Template VM ID `9000` matches `template_vm_id` in `terraform/envs/*/main.tf`. Adjust `STORAGE` to your datastore.

#### 2d. Create a runner VM and install the GitHub Actions agent

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

Clone the template created in step 2c and configure it via cloud-init:

```bash
RUNNER_ID=101
STORAGE=local-lvm

qm clone 9000 $RUNNER_ID --name github-runner --full
qm set $RUNNER_ID \
  --memory 2048 --cores 2 \
  --boot order=scsi0 \
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
| `SSH_PRIVATE_KEY`         | Contents of `~/.ssh/id_ed25519` on the Proxmox node (for Ansible)            |
| `ADGUARD_USERNAME`        | AdGuard admin username of your choice                                         |
| `ADGUARD_PASSWORD`        | AdGuard admin password of your choice                                         |
| `VAULT_USERNAME`          | Vault admin username of your choice                                           |
| `VAULT_PASSWORD`          | Vault admin password of your choice                                           |
| `POSTGRESQL_DB`           | PostgreSQL database name to create                                            |
| `POSTGRESQL_USER`         | PostgreSQL application user to create                                         |
| `POSTGRESQL_PASSWORD`     | PostgreSQL application user password                                          |
| `PGADMIN_EMAIL`           | pgAdmin admin login email of your choice                                      |
| `PGADMIN_PASSWORD`        | pgAdmin admin password of your choice                                         |
| `REDIS_PASSWORD`          | Redis auth password                                                           |
| `REDIS_COMMANDER_USER`    | Redis Commander web UI username                                               |
| `REDIS_COMMANDER_PASSWORD`| Redis Commander web UI password                                               |

### 3b. Proxmox — TLS certificate via Let's Encrypt

The default Proxmox cert is signed by its own internal CA, which browsers don't trust. Replace it with a Let's Encrypt cert using the Cloudflare DNS-01 challenge — no need to expose port 80.

**Get a Cloudflare API token** — My Profile → API Tokens → Create Token → Edit zone DNS → scope to `your-domain.com`. Copy the token.

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

### 4. GitHub — create environments (optional, for a prod gate)

Go to **Settings → Environments** and create three environments: `common`, `dev`, and `prod`.

Add a required reviewer to `prod` to require manual approval before applying — `common` and `dev` apply automatically on push to `main`.

---

## Services

### AdGuard Home

DNS ad-blocker running in an LXC container (`common` env, `192.168.1.2`).

**Secrets required** (GitHub → Settings → Secrets → Actions):

| Secret               | Value                         |
|----------------------|-------------------------------|
| `ADGUARD_USERNAME`   | Admin username of your choice |
| `ADGUARD_PASSWORD`   | Admin password of your choice |

**Deploy:**

1. Run **Terraform Apply** → `common` to create the LXC container.
2. Run **Ansible** → inventory `common`, playbook `adguard`.

AdGuard Home is available at `http://192.168.1.2` — no setup wizard, credentials are set from the secrets above.

**Point your router's DNS to `192.168.1.2`** (or set it per-device) to start filtering.

**To update AdGuard version** — bump `adguard_version` in `ansible/roles/adguard/defaults/main.yml` and re-run the Ansible workflow.

### HashiCorp Vault

Secret manager running in an LXC container (`common` env, `192.168.1.3`).

**Secrets required** (GitHub → Settings → Secrets → Actions):

| Secret             | Value                        |
|--------------------|------------------------------|
| `VAULT_USERNAME`   | Admin username — alphanumeric only, no `@` or special chars |
| `VAULT_PASSWORD`   | Admin password of your choice |

**Deploy:**

1. Run **Terraform Apply** → `common` to create the LXC container.
2. Run **Ansible** → inventory `common`, playbook `vault`.

The playbook initialises Vault (if not already done), unseals it, enables userpass auth, and creates the admin user. Vault is available at `http://192.168.1.3:8200`.

> The unseal key and root token are saved to `/root/vault-init.json` on the container — back this file up somewhere safe.

**To update Vault version** — bump `vault_version` in `ansible/roles/vault/defaults/main.yml` and re-run the Ansible workflow.

### PostgreSQL

Database server running in an LXC container (`common` env, `192.168.1.4`).

**Secrets required** (GitHub → Settings → Secrets → Actions):

| Secret                  | Value                                     |
|-------------------------|-------------------------------------------|
| `POSTGRESQL_DB`         | Database name to create                   |
| `POSTGRESQL_USER`       | Application user to create                |
| `POSTGRESQL_PASSWORD`   | Password for the application user         |

**Deploy:**

1. Run **Terraform Apply** → `common` to create the LXC container.
2. Run **Ansible** → inventory `common`, playbook `postgresql`.

PostgreSQL 16 listens on `192.168.1.4:5432`. The application user and database are created automatically. All hosts on `192.168.1.0/24` can connect using password auth (scram-sha-256).

### pgAdmin

Web-based PostgreSQL management UI running in an LXC container (`common` env, `192.168.1.5`).

**Secrets required** (GitHub → Settings → Secrets → Actions):

| Secret              | Value                              |
|---------------------|------------------------------------|
| `PGADMIN_EMAIL`     | Admin login email of your choice   |
| `PGADMIN_PASSWORD`  | Admin password of your choice      |

**Deploy:**

1. Run **Terraform Apply** → `common` to create the LXC container.
2. Run **Ansible** → inventory `common`, playbook `pgadmin`.

pgAdmin is available at `http://192.168.1.5`. To connect to PostgreSQL, add a new server in the UI:
- **Host:** `192.168.1.4`
- **Port:** `5432`
- **Username / Password:** the `POSTGRESQL_USER` / `POSTGRESQL_PASSWORD` secrets above

### Redis

Redis + Redis Commander web UI running in a single LXC container (`common` env, `192.168.1.6`).

**Secrets required** (GitHub → Settings → Secrets → Actions):

| Secret                     | Value                                    |
|----------------------------|------------------------------------------|
| `REDIS_PASSWORD`           | Redis auth password                      |
| `REDIS_COMMANDER_USER`     | Redis Commander web UI username          |
| `REDIS_COMMANDER_PASSWORD` | Redis Commander web UI password          |

**Deploy:**

1. Run **Terraform Apply** → `common` to create the LXC container.
2. Run **Ansible** → inventory `common`, playbook `redis`.

Redis listens on `192.168.1.6:6379` (password-protected). Redis Commander is available at `http://192.168.1.6:8081`.

### Kubernetes cluster (prod)

MicroK8s two-node cluster with an external HAProxy load balancer and NFS storage, all in the `prod` env.

| Host | Type | IP | Spec | Role |
|---|---|---|---|---|
| `prod-k8s-1` | VM | 192.168.1.110 | 4 CPU / 8 GB / 40 GB | MicroK8s node 1 |
| `prod-k8s-2` | VM | 192.168.1.111 | 4 CPU / 8 GB / 40 GB | MicroK8s node 2 |
| `prod-lb` | LXC | 192.168.1.109 | 1 CPU / 512 MB / 8 GB | HAProxy — external load balancer |
| `prod-nfs` | LXC | 192.168.1.108 | 1 CPU / 1 GB / 50 GB | NFS server — persistent volume storage |
| MetalLB pool | — | 192.168.1.120–130 | — | Virtual IPs for LoadBalancer services |

**Traffic flow:**
```
Internet → HAProxy (192.168.1.109) → MetalLB IP → Traefik → CrowdSec middleware → apps
```

**In-cluster components** (deployed via Flux CD):
- **MetalLB** — assigns IPs from the `192.168.1.120–130` pool to LoadBalancer services
- **Traefik** — ingress controller (gets a MetalLB IP)
- **CrowdSec** — DaemonSet + Traefik bouncer middleware for all ingress traffic
- **Flux CD** — GitOps operator watching `gitops/clusters/prod/`
- **External Secrets Operator** — syncs secrets from Vault (`192.168.1.3`) into K8s secrets

**Deploy:**

1. Run **Terraform Apply** → `prod` to create all four resources.
2. Run **Ansible** → inventory `prod`, playbook `microk8s` (builds and joins the cluster).
3. Run **Ansible** → inventory `prod`, playbook `haproxy` (configures the load balancer).
4. Run **Ansible** → inventory `prod`, playbook `nfs` (sets up exports + NFS CSI config).
5. Bootstrap Flux CD pointing at `gitops/clusters/prod/` in this repo.

---

## CI behaviour

| Event                       | Workflow              | What it does                              |
|-----------------------------|-----------------------|-------------------------------------------|
| Manual dispatch             | `terraform-apply.yml`   | Applies chosen env                      |
| Manual dispatch             | `terraform-destroy.yml` | Destroys chosen env                     |
| Manual dispatch             | `ansible.yml`         | Runs chosen playbook against chosen env   |

---

## Local init (one-time, per env)

```bash
export AWS_ACCESS_KEY_ID=<R2_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<R2_SECRET_ACCESS_KEY>
export AWS_ENDPOINT_URL_S3=<R2_ENDPOINT>

cd terraform/envs/dev   # or prod
terraform init -backend-config="bucket=<R2_BUCKET_NAME>"
```