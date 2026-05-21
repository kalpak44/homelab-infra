module "adguard" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 200
  hostname         = "adguard"
  template_file_id = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"

  ip_address = "192.168.1.2/24"
  gateway    = "192.168.1.1"

  memory_mb    = 256
  cpu_cores    = 1
  disk_size_gb = 4

  ssh_public_keys = [var.ssh_public_key]
}

variable "ssh_public_key" {
  type      = string
  sensitive = false
}