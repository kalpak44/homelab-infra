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