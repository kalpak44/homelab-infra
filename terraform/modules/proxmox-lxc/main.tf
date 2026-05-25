resource "proxmox_virtual_environment_container" "this" {
  node_name    = var.node_name
  vm_id        = var.container_id
  unprivileged = var.unprivileged
  started      = true
  start_on_boot = true

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      password = "root"
      keys     = var.ssh_public_keys
    }
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = 0
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [unprivileged, features]
  }
}