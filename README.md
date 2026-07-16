# homelab-infra

Terraform (state on Cloudflare R2) + Ansible + Flux CD GitOps for a Proxmox homelab. All deploy/destroy runs are triggered manually from GitHub Actions on a self-hosted runner, or locally via `just` recipes.

## Repository layout

```
homelab-infra/
├── terraform/     # Proxmox LXCs/VMs + Cloudflare records  →  see terraform/README.md
├── ansible/       # Post-provisioning for Proxmox services →  see ansible/README.md
├── gitops/        # Flux CD manifests (k3s workloads)      →  see gitops/README.md
└── .github/workflows/
    ├── cloudflare-deploy.yml    | Cloudflare - Deploy
    ├── cloudflare-destroy.yml   | Cloudflare - Destroy
    ├── proxmox-deploy.yml       | Proxmox    - Deploy
    ├── proxmox-destroy.yml      | Proxmox    - Destroy
    └── ansible-configure.yml    | Ansible    - Configure
```

Each Terraform resource has its own directory and its own R2 state file. Every service under `terraform/proxmox/` has a matching config recipe under `ansible/proxmox/`. Both layers expose a `just` interface (`just deploy`, `just destroy`, `just configure`) - the same command the workflows run.

Detailed usage lives in the sub-READMEs. This document covers **one-time setup** and the **service catalog**.

---

## Setup

### 1. Cloudflare R2 - create bucket and API token

1. Cloudflare dashboard → **R2** → **Create bucket** (e.g. `homelab-terraform-state`)
2. **R2 → Manage R2 API Tokens → Create Account API Token**
   - Permissions: **Object Read & Write**
   - Scope: the bucket you just created
3. Save the shown credentials:

   | Shown on screen       | Save as                |
   |-----------------------|------------------------|
   | **Access Key ID**     | `R2_ACCESS_KEY_ID`     |
   | **Secret Access Key** | `R2_SECRET_ACCESS_KEY` |

4. Copy the **S3 API** URL from the token page (`https://<account-id>.r2.cloudflarestorage.com`) → save as `R2_ENDPOINT`.

### 2. Proxmox - initial node setup

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

# Prints the token secret - copy it, shown only once
pveum user token add terraform@pve terraform --privsep 0
```

The username for Terraform is `terraform@pve!terraform`.

#### 2b. Enable snippet storage for cloud-init

```bash
pvesm set local --content images,rootdir,vztmpl,backup,snippets,iso
```

#### 2c. Base Proxmox artifacts (unmanaged by Terraform)

Because Terraform state is per-service and no dir "owns" the shared base template, these must exist on Proxmox before the first `just deploy proxmox <name>`:

1. Download the Ubuntu LXC template into `local:vztmpl/` (Proxmox UI → node → **local** → **CT Templates** → download `ubuntu-24.04-standard`).
2. Download the Ubuntu cloud image into `local:iso/` (`noble-server-cloudimg-amd64.img`).
3. Create VM **9000** (`ubuntu-2404-template`, template mode, 2 CPU / 2 GB / 20 GB disk from the cloud image, one vmbr0 NIC). This is the clone source for every proxmox-vm module usage.

Once these exist, service dirs adopt them by static ID - nothing else references them.

#### 2d. Runner VM and GitHub Actions agent

This VM runs the self-hosted runner and lives on the LAN so port 8006 is never exposed to the internet.

Ensure an SSH key exists on the Proxmox node (`ls ~/.ssh/`; `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""` if not).

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
qm set 101 --onboot 1     # start automatically after Proxmox reboots
```

SSH in and install tooling:

```bash
ssh ubuntu@192.168.1.101

sudo apt-get update && sudo apt-get install -y ansible python3-pip git curl unzip python3-passlib

# Terraform
wget -q -O /tmp/tf.zip https://releases.hashicorp.com/terraform/1.15.4/terraform_1.15.4_linux_amd64.zip
unzip /tmp/tf.zip terraform -d /tmp
sudo mv /tmp/terraform /usr/local/bin/terraform

# just (installed on-demand by the workflows via extractions/setup-just, but preinstalling is fine)
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin
```

Register the runner: repo → **Settings → Actions → Runners → New self-hosted runner** → Linux x64. Follow the shown steps on the VM, then install as a systemd service:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

### 3. GitHub - repository secrets

**Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Where to get it |
|---|---|
| `R2_ENDPOINT` | R2 S3 API URL, e.g. `https://<id>.r2.cloudflarestorage.com` |
| `R2_BUCKET_NAME` | Bucket name you created |
| `R2_ACCESS_KEY_ID` | From R2 token page |
| `R2_SECRET_ACCESS_KEY` | From R2 token page |
| `PROXMOX_ENDPOINT` | `https://<proxmox-ip>:8006` |
| `PROXMOX_USERNAME` | `terraform@pve!terraform` |
| `PROXMOX_PASSWORD` | Proxmox API token secret from 2a |
| `SSH_PUBLIC_KEY` | Contents of `~/.ssh/id_ed25519.pub` on Proxmox |
| `SSH_PRIVATE_KEY` | Contents of `~/.ssh/id_ed25519` on Proxmox (Ansible SSH auth fallback) |
| `HOST_PASSWORD` | Root password for every LXC/VM (SSH + Proxmox console). Terraform bakes it into new hosts; Ansible rotates it on existing ones |
| `PUBLIC_WAN_IP` | Your WAN IP - used for public Cloudflare A records |
| `CLOUDFLARE_API_TOKEN` | Cloudflare token with `Zone:DNS:Edit` + email routing perms (see below) |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt registration |
| `ADGUARD_USERNAME`, `ADGUARD_PASSWORD` | AdGuard admin creds |
| `VAULT_USERNAME`, `VAULT_PASSWORD` | Vault admin creds (alphanumeric) |
| `POSTGRESQL_DB`, `POSTGRESQL_USER`, `POSTGRESQL_PASSWORD` | Postgres bootstrap creds |
| `PGADMIN_EMAIL`, `PGADMIN_PASSWORD` | pgAdmin admin creds |
| `REDIS_PASSWORD`, `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD` | Redis + Commander UI creds |
| `RABBITMQ_USER`, `RABBITMQ_PASSWORD` | RabbitMQ admin creds |
| `FLUX_GITHUB_TOKEN` | GitHub PAT with `repo` scope - Flux CD bootstrap |

### 4. Cloudflare API token - required scopes

The single `CLOUDFLARE_API_TOKEN` needs:

| Type | Resource | Permission |
|---|---|---|
| Zone | DNS | Edit |
| Account | Email Routing Addresses | Edit + Read |
| Zone | Email Routing Rules | Edit + Read |
| Zone | Zone Settings | Edit + Read |

Zone resource is scoped to your domain (e.g. `pavel-usanli.online`).

### 5. Proxmox - Let's Encrypt cert for the web UI

Replace the default self-signed cert with Let's Encrypt via Cloudflare DNS-01:

```bash
pvenode acme account register default your@email.com \
  --directory https://acme-v02.api.letsencrypt.org/directory

echo "CF_Token=<cloudflare-api-token>" > /tmp/cf.env
pvenode acme plugin add dns cloudflare --api cf --data /tmp/cf.env
rm /tmp/cf.env

pvenode config set \
  --acme account=default \
  --acmedomain0 domain=<proxmox-hostname>.<your-domain>,plugin=cloudflare

pvenode acme cert order
```

Renewal is automatic via a built-in systemd timer.

---

## Services

All services live behind `*.internal.pavel-usanli.online` (LAN only, unproxied) or `*.pavel-usanli.online` (public, proxied through Cloudflare). Deploy order: Terraform (creates the box + DNS record) → Ansible (configures the service).

| Service | Where | IP | Terraform dir | Ansible dir |
|---|---|---|---|---|
| AdGuard Home | LXC | 192.168.1.2 | `proxmox/adguard-lxc` | `proxmox/adguard-lxc` |
| Vault | LXC | 192.168.1.3 | `proxmox/vault-lxc` | `proxmox/vault-lxc` |
| PostgreSQL + pgAdmin | LXC | 192.168.1.4 | `proxmox/postgres-lxc` | `proxmox/postgres-lxc` |
| Redis + Commander | LXC | 192.168.1.6 | `proxmox/redis-lxc` | `proxmox/redis-lxc` |
| Portainer | VM | 192.168.1.7 | `proxmox/portainer-vm` | `proxmox/portainer-vm` |
| RabbitMQ | LXC | 192.168.1.8 | `proxmox/rabbitmq-lxc` | `proxmox/rabbitmq-lxc` |
| NFS server (k3s PVs) | VM | 192.168.1.108 | `proxmox/nfs-vm` | `proxmox/nfs-vm` |
| k3s control plane | VM | 192.168.1.110 | `proxmox/k3s-cluster` | `proxmox/k3s-cluster` (`cluster-setup.yml`) |
| k3s worker | VM | 192.168.1.111 | `proxmox/k3s-cluster` | (same) |
| Flux CD bootstrap | - | (on k3s) | - | `proxmox/k3s-cluster` (`flux-install.yml`) |
| Cloudflare email routing | Cloudflare | - | `cloudflare/shared/cloudflare-email` | - |

### Per-service notes

**AdGuard Home** - Point your router's DNS to `192.168.1.2` (or set it per-device). UI at `https://adguard.internal.pavel-usanli.online`. To bump versions edit `ansible/proxmox/adguard-lxc/roles/adguard/defaults/main.yml`.

**Vault** - Playbook initialises, unseals, enables userpass auth, and creates the admin. Unseal key and root token are saved to `/root/vault-init.json` inside the container - **back this file up**. UI at `http://vault.internal.pavel-usanli.online:8200`.

**PostgreSQL + pgAdmin** - Both roles run in a single `just configure postgres-lxc`. Postgres listens on `192.168.1.4:5432`; pgAdmin at `https://pgadmin.internal.pavel-usanli.online`. All hosts on `192.168.1.0/24` connect with password auth (scram-sha-256).

**Redis** - Redis on `192.168.1.6:6379`, Commander UI at `http://redis.internal.pavel-usanli.online:8081`.

**RabbitMQ** - AMQP on `192.168.1.8:5672`. Management UI at `https://rabbitmq.internal.pavel-usanli.online`.

**Portainer** - Docker + nginx + certbot inside the VM. UI at `https://portainer.internal.pavel-usanli.online`. First visit shows a setup wizard - create the admin there within 5 minutes of the first launch (`sudo docker restart portainer` to re-open if it times out).

**k3s cluster** - Two-node cluster (control plane + worker). `just configure k3s-cluster` runs the 3-phase bootstrap (prep nodes → install server on k3s-1 → join k3s-2). Then `just configure k3s-cluster/flux` installs Flux CD, which reconciles everything under `gitops/clusters/homelab/`.

To use `kubectl` locally on the `192.168.1.0/24` network:

```bash
scp ubuntu@192.168.1.110:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab.yaml
sed -i '' 's/127.0.0.1/192.168.1.110/' ~/.kube/homelab.yaml
export KUBECONFIG=~/.kube/homelab.yaml
kubectl get nodes
```

**Cloudflare email routing** - `contact@pavel-usanli.online` forwards to your Gmail. First deploy triggers a verification email from Cloudflare - click the link in the forwarded message to activate.

For sending from `contact@…` via Gmail: **Gmail → Settings → Accounts → Send mail as → Add**, backed by Mailjet SMTP (`in-v3.mailjet.com:587`, TLS). Gmail sends its own verification email; approve via the forwarded link. Optional DMARC record:

```
TXT _dmarc.pavel-usanli.online  →  v=DMARC1; p=none; rua=mailto:contact@pavel-usanli.online
```

Start with `p=none` and tighten to `p=quarantine` / `p=reject` after reports confirm all senders pass SPF/DKIM.

---

## In-cluster services (Flux CD)

Not managed by Terraform or Ansible - Flux reconciles these from `gitops/clusters/homelab/`. See [`gitops/README.md`](gitops/README.md) for the full list.

Highlights:
- **MetalLB** - LoadBalancer IP pool `192.168.1.120–130`
- **Traefik** - ingress at `192.168.1.120`, TLS via Cloudflare DNS-01
- **cert-manager** - issues Let's Encrypt certs
- **External Secrets Operator** - syncs Vault → k8s secrets
- **CrowdSec** - IDS/IPS + AppSec middleware
- **NFS provisioner** - StorageClass `nfs` backed by `192.168.1.108:/srv/nfs/k8s`

---

## CI

Five workflows, all `workflow_dispatch` (manual), all running on the self-hosted runner:

| Workflow | Picks | Runs |
|---|---|---|
| `cloudflare-deploy.yml` | 21 cloudflare/ dirs | `just deploy cloudflare <resource>` |
| `cloudflare-destroy.yml` | 21 cloudflare/ dirs | `just destroy cloudflare <resource>` |
| `proxmox-deploy.yml` | 8 proxmox/ services | `just deploy proxmox <resource>` |
| `proxmox-destroy.yml` | 8 proxmox/ services | `just destroy proxmox <resource>` |
| `ansible-configure.yml` | 8 services + `k3s-cluster/flux` | `just configure <resource>` |

Each workflow is a single `just` command - all logic lives in the Justfiles under `terraform/` and `ansible/`. See [`terraform/README.md`](terraform/README.md) and [`ansible/README.md`](ansible/README.md).

## Local development

Same commands the workflows run:

```bash
cd terraform && just list                              # every deployable
cd terraform && just deploy proxmox adguard-lxc        # provision the LXC
cd ansible   && just configure adguard-lxc             # then configure it
cd terraform && just destroy proxmox adguard-lxc       # tear down
```

Locally you need the same env vars listed in the workflow files (`~/.zshrc` or `~/.zshenv` works).

### Host SSH — unified root + password auth

All LXCs and VMs share a single OS-level identity: **user `root`** with the password in `HOST_PASSWORD`.
Ansible connects with `ansible_user: root` and `ansible_ssh_pass=$HOST_PASSWORD` (via `hosts.yml`).
The same password is what you type into the Proxmox web UI console/VNC.

`sshpass` is installed by the ansible `Justfile` on first `just configure` (Linux via apt, macOS via
homebrew). CI still uses `SSH_PRIVATE_KEY` when set — Ansible prefers key over password when both work.

**One-time enable for pre-existing VMs (portainer, nfs, k3s-1, k3s-2)**

VMs were provisioned with `ubuntu` as the cloud-init user, so before the first unified `just configure`
you need to enable root SSH once (per VM):

```bash
ssh ubuntu@<vm-ip> "sudo bash -c '
  echo root:$HOST_PASSWORD | chpasswd &&
  sed -i s/^#?PermitRootLogin.*/PermitRootLogin\ yes/ /etc/ssh/sshd_config &&
  sed -i s/^#?PasswordAuthentication.*/PasswordAuthentication\ yes/ /etc/ssh/sshd_config &&
  systemctl restart ssh
'"
```

After that, `just configure` uses `root@<vm-ip>` like every other host. New VMs pick up the unified
identity from the Ansible `pre_tasks` in each playbook.