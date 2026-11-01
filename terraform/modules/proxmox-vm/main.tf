resource "proxmox_virtual_environment_vm" "this" {
  node_name = var.node_name
  name      = var.vm_name
  vm_id     = var.vm_id
  on_boot   = true

  clone {
    vm_id = var.template_vm_id
    full  = false
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  # discard = "on" so the guest's fstrim actually reaches the thin pool. With the
  # provider default the blocks a guest frees stay allocated for ever: the k3s nodes
  # reported 81% used while their thin volumes sat at 97%, and fstrim.timer inside them
  # had been running against a disk that ignored it.
  #
  # Applying this to a running VM needs a power cycle through Proxmox — `qm reboot`, not a
  # reboot from inside. A guest reboot keeps the same QEMU process, which holds the device
  # flag it started with, so the setting reads as applied in `qm config` and is still
  # `discard=ignore` in the process actually serving the disk.
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    file_format  = "raw"
    size         = var.disk_size_gb
    discard      = "on"
  }

  dynamic "disk" {
    for_each = var.data_disk_size_gb > 0 ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      file_format  = "raw"
      size         = var.data_disk_size_gb
      discard      = "on"
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  initialization {
    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      username = "root"
      password = var.password
      keys     = var.ssh_public_keys
    }

    vendor_data_file_id = "local:snippets/vm-ssh-password.yaml"
  }

  agent {
    enabled = true
    timeout = "1m"
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}