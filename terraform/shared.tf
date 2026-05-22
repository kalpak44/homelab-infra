data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "proxmox" {
  zone_id = data.cloudflare_zone.this.id
  name    = "proxmox.internal"
  content = "192.168.1.50"
  type    = "A"
  proxied = false
}

resource "proxmox_download_file" "ubuntu_lxc" {
  content_type        = "vztmpl"
  datastore_id        = "local"
  node_name           = "proxmox"
  url                 = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  overwrite_unmanaged = true
}

resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type        = "iso"
  datastore_id        = "local"
  node_name           = "proxmox"
  url                 = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name           = "noble-server-cloudimg-amd64.img"
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name      = "ubuntu-2404-template"
  node_name = "proxmox"
  vm_id     = 9000
  template  = true
  started   = false

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    file_format  = "raw"
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [template]
  }
}