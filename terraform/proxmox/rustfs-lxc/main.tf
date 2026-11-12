module "lxc" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 213
  hostname         = "rustfs"
  template_file_id = var.lxc_template_file_id

  ip_address = "192.168.1.13/24"
  gateway    = "192.168.1.1"

  cpu_cores = 1
  memory_mb = 256

  # Objects sit on their own volume, so a root disk that fills with logs or an upgrade
  # cannot take them with it. /data/rustfs on it is the path the package's unit may write.
  disk_size_gb      = 20
  data_disk_size_gb = 100
  data_disk_path    = "/data"

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}
