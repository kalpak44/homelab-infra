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
    size         = var.disk_size_gb
    interface    = "scsi0"
    file_format  = "raw"
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
      keys = var.ssh_public_keys
    }

    user_data_file_id = var.cloud_init_file_id
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}