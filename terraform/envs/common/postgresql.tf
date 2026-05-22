module "postgresql" {
  source = "../../modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 202
  hostname         = "postgresql"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.4/24"
  gateway    = "192.168.1.1"

  memory_mb    = 2048
  cpu_cores    = 1
  disk_size_gb = 16

  ssh_public_keys = [var.ssh_public_key]
}

resource "cloudflare_record" "postgresql" {
  zone_id = data.cloudflare_zone.this.id
  name    = "postgresql.internal"
  content = "192.168.1.4"
  type    = "A"
  proxied = false
}

resource "cloudflare_record" "pgadmin" {
  zone_id = data.cloudflare_zone.this.id
  name    = "pgadmin.internal"
  content = "192.168.1.4"
  type    = "A"
  proxied = false
}