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