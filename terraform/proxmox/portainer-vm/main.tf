module "vm" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "portainer"
  vm_id          = 302
  template_vm_id = var.vm_template_id

  ip_address = "192.168.1.7/24"
  gateway    = "192.168.1.1"

  cpu_cores         = 2
  memory_mb         = 4096
  disk_size_gb      = 20
  data_disk_size_gb = 512

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}