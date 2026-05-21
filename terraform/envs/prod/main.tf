variable "ssh_public_key" {
  type    = string
  default = ""
}

# ── LXC template ────────────────────────────────────────────────────────────

resource "proxmox_download_file" "ubuntu_lxc" {
  content_type        = "vztmpl"
  datastore_id        = "local"
  node_name           = "proxmox"
  url                 = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  overwrite_unmanaged = true
}

# ── Existing VM ──────────────────────────────────────────────────────────────

module "prod_vm" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-hello-world"
  vm_id          = 100
  template_vm_id = 9000

  cpu_cores    = 4
  memory_mb    = 4096
  disk_size_gb = 40

  ip_address = "192.168.1.100/24"
  gateway    = "192.168.1.1"
}

# ── Kubernetes nodes ─────────────────────────────────────────────────────────

module "prod_k8s_1" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-k8s-1"
  vm_id          = 110
  template_vm_id = 9000

  cpu_cores    = 4
  memory_mb    = 8192
  disk_size_gb = 40

  ip_address      = "192.168.1.110/24"
  gateway         = "192.168.1.1"
  ssh_public_keys = [var.ssh_public_key]
}

module "prod_k8s_2" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-k8s-2"
  vm_id          = 111
  template_vm_id = 9000

  cpu_cores    = 4
  memory_mb    = 8192
  disk_size_gb = 40

  ip_address      = "192.168.1.111/24"
  gateway         = "192.168.1.1"
  ssh_public_keys = [var.ssh_public_key]
}

# ── HAProxy load balancer ────────────────────────────────────────────────────

module "prod_lb" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 300
  hostname         = "prod-lb"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.109/24"
  gateway    = "192.168.1.1"

  memory_mb    = 512
  cpu_cores    = 1
  disk_size_gb = 8

  ssh_public_keys = [var.ssh_public_key]
}

# ── NFS storage ──────────────────────────────────────────────────────────────

module "prod_nfs" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 301
  hostname         = "prod-nfs"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.108/24"
  gateway    = "192.168.1.1"

  memory_mb    = 1024
  cpu_cores    = 1
  disk_size_gb = 50

  ssh_public_keys = [var.ssh_public_key]
}