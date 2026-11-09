module "lxc" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 212
  hostname         = "grafana"
  template_file_id = var.lxc_template_file_id

  ip_address = "192.168.1.12/24"
  gateway    = "192.168.1.1"

  cpu_cores = 1
  memory_mb = 512

  # Dashboards, alert rules and datasources are provisioned from Ansible, so the only
  # state on this disk is the SQLite database of users and sessions.
  disk_size_gb = 8

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}
