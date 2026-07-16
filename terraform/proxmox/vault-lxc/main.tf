module "lxc" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 201
  hostname         = "vault"
  template_file_id = var.lxc_template_file_id

  ip_address = "192.168.1.3/24"
  gateway    = "192.168.1.1"

  cpu_cores    = 1
  memory_mb    = 512
  disk_size_gb = 8

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}