variable "ssh_public_key" {
  type    = string
  default = ""
}

module "prod_vm" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "prod-hello-world"
  vm_id          = 100
  template_vm_id = 9000

  cpu_cores    = 4
  memory_mb    = 4096
  disk_size_gb = 40

  ip_address = "192.168.1.100/24"
  gateway    = "192.168.1.1"
}