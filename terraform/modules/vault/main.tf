module "lxc" {
  source = "../proxmox-lxc"

  node_name        = "proxmox"
  container_id     = 201
  hostname         = "vault"
  template_file_id = var.template_file_id

  ip_address = "192.168.1.3/24"
  gateway    = "192.168.1.1"

  memory_mb    = 512
  cpu_cores    = 1
  disk_size_gb = 8

  ssh_public_keys = var.ssh_public_keys
}

resource "cloudflare_record" "vault" {
  zone_id = var.zone_id
  name    = "vault.internal"
  content = "192.168.1.3"
  type    = "A"
  proxied = false
}