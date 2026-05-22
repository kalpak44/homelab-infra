module "lxc" {
  source = "../proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 202
  hostname         = "postgres"
  template_file_id = var.template_file_id

  ip_address = "192.168.1.4/24"
  gateway    = "192.168.1.1"

  memory_mb    = 2048
  cpu_cores    = 1
  disk_size_gb = 16

  ssh_public_keys = var.ssh_public_keys
}

resource "cloudflare_record" "postgres" {
  zone_id = var.zone_id
  name    = "postgres.internal"
  content = "192.168.1.4"
  type    = "A"
  proxied = false
}

resource "cloudflare_record" "pgadmin" {
  zone_id = var.zone_id
  name    = "pgadmin.internal"
  content = "192.168.1.4"
  type    = "A"
  proxied = false
}