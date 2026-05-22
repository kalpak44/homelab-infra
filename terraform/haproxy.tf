module "prod_lb" {
  source = "./modules/proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 300
  hostname         = "prod-lb"
  template_file_id = proxmox_download_file.ubuntu_lxc.id

  ip_address = "192.168.1.109/24"
  gateway    = "192.168.1.1"

  memory_mb    = 512
  cpu_cores    = 1
  disk_size_gb = 8

  ssh_public_keys = [var.ssh_public_key]
}

resource "cloudflare_record" "haproxy" {
  zone_id = data.cloudflare_zone.this.id
  name    = "haproxy.internal"
  content = "192.168.1.109"
  type    = "A"
  proxied = false
}