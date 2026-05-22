module "prod_k3s_1" {
  source = "./modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-k3s-1"
  vm_id          = 110
  template_vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id

  cpu_cores    = 4
  memory_mb    = 8192
  disk_size_gb = 40

  ip_address      = "192.168.1.110/24"
  gateway         = "192.168.1.1"
  ssh_public_keys = [var.ssh_public_key]
}

module "prod_k3s_2" {
  source = "./modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-k3s-2"
  vm_id          = 111
  template_vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id

  cpu_cores    = 4
  memory_mb    = 8192
  disk_size_gb = 40

  ip_address      = "192.168.1.111/24"
  gateway         = "192.168.1.1"
  ssh_public_keys = [var.ssh_public_key]
}