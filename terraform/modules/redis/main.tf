module "lxc" {
  source = "../proxmox-lxc"

  node_name        = "proxmox"
  container_id     = var.container_id
  hostname         = "redis"
  template_file_id = var.template_file_id

  ip_address = "${var.ip_address}/24"
  gateway    = var.gateway

  cpu_cores    = var.cpu_cores
  memory_mb    = var.memory_mb
  disk_size_gb = var.disk_size_gb

  ssh_public_keys = var.ssh_public_keys
}

resource "cloudflare_record" "redis" {
  zone_id = var.zone_id
  name    = "redis.internal"
  content = var.ip_address
  type    = "A"
  proxied = false
}