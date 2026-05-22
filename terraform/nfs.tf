module "prod_nfs" {
  source = "./modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-nfs"
  vm_id          = 301
  template_vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id

  cpu_cores         = 2
  memory_mb         = 2048
  disk_size_gb      = 20
  data_disk_size_gb = 512

  ip_address      = "192.168.1.108/24"
  gateway         = "192.168.1.1"
  ssh_public_keys = [var.ssh_public_key]
}

resource "cloudflare_record" "nfs" {
  zone_id = data.cloudflare_zone.this.id
  name    = "nfs.internal"
  content = "192.168.1.108"
  type    = "A"
  proxied = false
}