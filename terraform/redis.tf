module "redis" {
  source = "./modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 204
  hostname         = "redis"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.6/24"
  gateway    = "192.168.1.1"

  memory_mb    = 512
  cpu_cores    = 1
  disk_size_gb = 4

  ssh_public_keys = [var.ssh_public_key]
}

resource "cloudflare_record" "redis" {
  zone_id = data.cloudflare_zone.this.id
  name    = "redis.internal"
  content = "192.168.1.6"
  type    = "A"
  proxied = false
}