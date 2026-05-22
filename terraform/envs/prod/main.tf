variable "ssh_public_key" {
  type    = string
  default = ""
}

# ── Ubuntu cloud image ───────────────────────────────────────────────────────

resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type        = "iso"
  datastore_id        = "local"
  node_name           = "proxmox"
  url                 = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name           = "noble-server-cloudimg-amd64.img"
  overwrite_unmanaged = true
}

# ── Golden template (SSH needed once here) ───────────────────────────────────

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name      = "ubuntu-2404-template"
  node_name = "proxmox"
  vm_id     = 9000
  template  = true
  started   = false

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    file_format  = "raw"
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
  }
}

# ── LXC template ────────────────────────────────────────────────────────────

resource "proxmox_download_file" "ubuntu_lxc" {
  content_type        = "vztmpl"
  datastore_id        = "local"
  node_name           = "proxmox"
  url                 = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  overwrite_unmanaged = true
}

# ── Kubernetes nodes (clone — pure API) ──────────────────────────────────────

module "prod_k8s_1" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-k8s-1"
  vm_id          = 110
  template_vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id

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
  template_vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id

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

  ip_address   = "192.168.1.108/24"
  gateway      = "192.168.1.1"
  unprivileged = true

  memory_mb    = 1024
  cpu_cores    = 1
  disk_size_gb = 256

  ssh_public_keys = [var.ssh_public_key]
}