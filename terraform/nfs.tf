module "nfs" {
  source          = "./modules/nfs"
  zone_id         = data.cloudflare_zone.this.id
  template_vm_id  = proxmox_virtual_environment_vm.ubuntu_template.vm_id
  ssh_public_keys = [var.ssh_public_key]
}