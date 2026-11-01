module "node_1" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "k3s-1"
  vm_id          = 110
  template_vm_id = var.vm_template_id

  ip_address = "192.168.1.110/24"
  gateway    = "192.168.1.1"

  cpu_cores = 4
  memory_mb = 8192
  # 40G left both nodes at 81-84%: containerd keeps every image a deploy supersedes, so
  # the floor only ever rises. Kubelet's image GC holds it under 85% by evicting images
  # that may be needed again, which is cheaper to avoid than to tune.
  disk_size_gb = 80

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}

module "node_2" {
  source = "../../modules/proxmox-vm"

  node_name      = "proxmox"
  vm_name        = "k3s-2"
  vm_id          = 111
  template_vm_id = var.vm_template_id

  ip_address = "192.168.1.111/24"
  gateway    = "192.168.1.1"

  cpu_cores = 4
  memory_mb = 8192
  # 40G left both nodes at 81-84%: containerd keeps every image a deploy supersedes, so
  # the floor only ever rises. Kubelet's image GC holds it under 85% by evicting images
  # that may be needed again, which is cheaper to avoid than to tune.
  disk_size_gb = 80

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}