module "vm" {
  source = "../proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "portainer"
  vm_id          = var.vm_id
  template_vm_id = var.template_vm_id

  ip_address = "${var.ip_address}/24"
  gateway    = var.gateway

  cpu_cores    = var.cpu_cores
  memory_mb    = var.memory_mb
  disk_size_gb = var.disk_size_gb

  ssh_public_keys = var.ssh_public_keys
}

resource "cloudflare_record" "portainer" {
  zone_id = var.zone_id
  name    = "portainer.internal"
  content = var.ip_address
  type    = "A"
  proxied = false
}