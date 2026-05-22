module "lxc" {
  source = "../proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 200
  hostname         = "adguard"
  template_file_id = var.template_file_id

  ip_address = "192.168.1.2/24"
  gateway    = "192.168.1.1"

  memory_mb    = 256
  cpu_cores    = 1
  disk_size_gb = 4

  ssh_public_keys = var.ssh_public_keys
}

resource "cloudflare_record" "adguard" {
  zone_id = var.zone_id
  name    = "adguard.internal"
  content = "192.168.1.2"
  type    = "A"
  proxied = false
}