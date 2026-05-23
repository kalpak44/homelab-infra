# ─── LXC containers ──────────────────────────────────────────────────────────

# AdGuard Home — DNS ad-blocker and network-wide filter
module "adguard" {
  source           = "./modules/adguard"
  zone_id          = data.cloudflare_zone.this.id
  template_file_id = proxmox_download_file.ubuntu_lxc.id
  ssh_public_keys  = [var.ssh_public_key]

  container_id = 200
  ip_address   = "192.168.1.2"
  cpu_cores    = 1
  memory_mb    = 256
  disk_size_gb = 4
}

# HashiCorp Vault — secrets manager
module "vault" {
  source           = "./modules/vault"
  zone_id          = data.cloudflare_zone.this.id
  template_file_id = proxmox_download_file.ubuntu_lxc.id
  ssh_public_keys  = [var.ssh_public_key]

  container_id = 201
  ip_address   = "192.168.1.3"
  cpu_cores    = 1
  memory_mb    = 512
  disk_size_gb = 8
}

# PostgreSQL + pgAdmin — database server and web UI
module "postgres" {
  source           = "./modules/postgres"
  zone_id          = data.cloudflare_zone.this.id
  template_file_id = proxmox_download_file.ubuntu_lxc.id
  ssh_public_keys  = [var.ssh_public_key]

  container_id = 202
  ip_address   = "192.168.1.4"
  cpu_cores    = 1
  memory_mb    = 2048
  disk_size_gb = 16
}

# Redis + Redis Commander — cache and web UI
module "redis" {
  source           = "./modules/redis"
  zone_id          = data.cloudflare_zone.this.id
  template_file_id = proxmox_download_file.ubuntu_lxc.id
  ssh_public_keys  = [var.ssh_public_key]

  container_id = 204
  ip_address   = "192.168.1.6"
  cpu_cores    = 1
  memory_mb    = 512
  disk_size_gb = 4
}

# Portainer — Docker management UI
module "portainer" {
  source           = "./modules/portainer"
  zone_id          = data.cloudflare_zone.this.id
  template_file_id = proxmox_download_file.ubuntu_lxc.id
  ssh_public_keys  = [var.ssh_public_key]

  container_id = 205
  ip_address   = "192.168.1.7"
  cpu_cores    = 1
  memory_mb    = 1024
  disk_size_gb = 10
}

# HAProxy — external load balancer for the k3s cluster
module "haproxy" {
  source           = "./modules/haproxy"
  zone_id          = data.cloudflare_zone.this.id
  template_file_id = proxmox_download_file.ubuntu_lxc.id
  ssh_public_keys  = [var.ssh_public_key]

  container_id = 300
  ip_address   = "192.168.1.109"
  cpu_cores    = 1
  memory_mb    = 512
  disk_size_gb = 8
}

# ─── VMs ─────────────────────────────────────────────────────────────────────

# NFS server — persistent volume storage for k3s (StorageClass: nfs)
module "nfs" {
  source          = "./modules/nfs"
  zone_id         = data.cloudflare_zone.this.id
  template_vm_id  = proxmox_virtual_environment_vm.ubuntu_template.vm_id
  ssh_public_keys = [var.ssh_public_key]

  vm_id             = 301
  ip_address        = "192.168.1.108"
  cpu_cores         = 2
  memory_mb         = 2048
  disk_size_gb      = 20  # OS disk
  data_disk_size_gb = 512 # NFS data disk mounted at /srv/nfs
}

# k3s cluster — two-node control-plane + worker, managed by Flux CD
module "k3s" {
  source          = "./modules/k3s"
  template_vm_id  = proxmox_virtual_environment_vm.ubuntu_template.vm_id
  ssh_public_keys = [var.ssh_public_key]

  node1_id = 110
  node1_ip = "192.168.1.110" # k3s-1 — control plane

  node2_id = 111
  node2_ip = "192.168.1.111" # k3s-2 — worker

  cpu_cores    = 4
  memory_mb    = 8192
  disk_size_gb = 40
}