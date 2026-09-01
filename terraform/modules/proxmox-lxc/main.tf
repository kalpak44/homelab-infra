resource "proxmox_virtual_environment_container" "this" {
  node_name     = var.node_name
  vm_id         = var.container_id
  unprivileged  = var.unprivileged
  started       = true
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
      password = var.password
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

  dynamic "mount_point" {
    for_each = var.data_disk_size_gb > 0 ? [1] : []

    content {
      volume = var.datastore_id
      size   = "${var.data_disk_size_gb}G"
      path   = var.data_disk_path
    }
  }

  network_interface {
    name     = "eth0"
    bridge   = var.network_bridge
    firewall = var.firewall_enabled
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [initialization, unprivileged, features]
  }
}