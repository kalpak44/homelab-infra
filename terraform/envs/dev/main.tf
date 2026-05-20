module "dev_vm" {
  source = "../../modules/proxmox-vm"

  node_name      = "pve"
  vm_name        = "dev-hello-world"
  vm_id          = 200
  template_vm_id = 9000

  cpu_cores    = 2
  memory_mb    = 2048
  disk_size_gb = 20

  ip_address = "192.168.1.200/24"
  gateway    = "192.168.1.1"
}