module "lxc" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 206
  hostname         = "whisper"
  template_file_id = var.lxc_template_file_id

  ip_address = "192.168.1.9/24"
  gateway    = "192.168.1.1"

  cpu_cores    = 2
  memory_mb    = 3072
  disk_size_gb = 8

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}