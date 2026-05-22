module "lxc" {
  source = "../proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 300
  hostname         = "haproxy"
  template_file_id = var.template_file_id

  ip_address = "192.168.1.109/24"
  gateway    = "192.168.1.1"

  memory_mb    = 512
  cpu_cores    = 1
  disk_size_gb = 8

  ssh_public_keys = var.ssh_public_keys
}

resource "cloudflare_record" "haproxy" {
  zone_id = var.zone_id
  name    = "haproxy.internal"
  content = "192.168.1.109"
  type    = "A"
  proxied = false
}