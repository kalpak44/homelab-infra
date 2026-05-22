module "k3s" {
  source          = "./modules/k3s"
  template_vm_id  = proxmox_virtual_environment_vm.ubuntu_template.vm_id
  ssh_public_keys = [var.ssh_public_key]
}