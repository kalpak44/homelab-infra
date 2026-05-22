module "node_1" {
  source = "../proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-k3s-1"
  vm_id          = var.node1_id
  template_vm_id = var.template_vm_id

  cpu_cores    = var.cpu_cores
  memory_mb    = var.memory_mb
  disk_size_gb = var.disk_size_gb

  ip_address      = "${var.node1_ip}/24"
  gateway         = var.gateway
  ssh_public_keys = var.ssh_public_keys
}

module "node_2" {
  source = "../proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-k3s-2"
  vm_id          = var.node2_id
  template_vm_id = var.template_vm_id

  cpu_cores    = var.cpu_cores
  memory_mb    = var.memory_mb
  disk_size_gb = var.disk_size_gb

  ip_address      = "${var.node2_ip}/24"
  gateway         = var.gateway
  ssh_public_keys = var.ssh_public_keys
}