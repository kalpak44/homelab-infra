resource "proxmox_virtual_environment_container" "this" {
  node_name     = "proxmox"
  vm_id         = var.container_id
  unprivileged  = false
  started       = false
  start_on_boot = true

  initialization {
    hostname = "dpi"

    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.gateway
      }
    }

    user_account {
      password = "ubuntu"
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
    datastore_id = "local-lvm"
    size         = var.disk_size_gb
  }

  # LAN interface — internet egress + management
  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  # AP-facing interface — WiFi clients connect through this
  network_interface {
    name   = "eth1"
    bridge = "vmbr2"
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  lifecycle {
    ignore_changes = [unprivileged]
  }
}

resource "cloudflare_record" "ntopng" {
  zone_id = var.zone_id
  name    = "ntopng.internal"
  content = var.ip_address
  type    = "A"
  proxied = false
}