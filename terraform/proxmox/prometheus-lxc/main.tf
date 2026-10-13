module "lxc" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 211
  hostname         = "prometheus"
  template_file_id = var.lxc_template_file_id

  ip_address = "192.168.1.11/24"
  gateway    = "192.168.1.1"

  cpu_cores = 2
  memory_mb = 1024

  # The TSDB sits on its own volume, so a root disk that fills with logs or an
  # upgrade cannot take the samples with it. Its size caps retention — the
  # matching cap is in ansible/proxmox/prometheus-lxc/roles/prometheus/defaults/main.yml.
  disk_size_gb      = 8
  data_disk_size_gb = 20
  data_disk_path    = "/var/lib/prometheus"

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}
