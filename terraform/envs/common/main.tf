resource "proxmox_download_file" "ubuntu_lxc" {
  content_type        = "vztmpl"
  datastore_id        = "local"
  node_name           = "proxmox"
  url                 = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  overwrite_unmanaged = true
}

module "adguard" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 200
  hostname         = "adguard"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.2/24"
  gateway    = "192.168.1.1"

  memory_mb    = 256
  cpu_cores    = 1
  disk_size_gb = 4

  ssh_public_keys = [var.ssh_public_key]
}

module "vault" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 201
  hostname         = "vault"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.3/24"
  gateway    = "192.168.1.1"

  memory_mb    = 512
  cpu_cores    = 1
  disk_size_gb = 8

  ssh_public_keys = [var.ssh_public_key]
}

module "postgresql" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 202
  hostname         = "postgresql"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.4/24"
  gateway    = "192.168.1.1"

  memory_mb    = 1024
  cpu_cores    = 1
  disk_size_gb = 10

  ssh_public_keys = [var.ssh_public_key]
}

module "pgadmin" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 203
  hostname         = "pgadmin"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.5/24"
  gateway    = "192.168.1.1"

  memory_mb    = 512
  cpu_cores    = 1
  disk_size_gb = 4

  ssh_public_keys = [var.ssh_public_key]
}

variable "ssh_public_key" {
  type      = string
  sensitive = false
}