resource "proxmox_virtual_environment_vm" "this" {
  node_name = var.node_name
  name      = var.vm_name
  vm_id     = var.vm_id

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    file_format  = "raw"
    size         = var.disk_size_gb
  }

  network_device {
    bridge = var.network_bridge
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = var.ssh_public_keys
    }
  }

  agent {
    enabled = true
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}