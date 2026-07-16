data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "nocobase" {
  zone_id = data.cloudflare_zone.this.id
  name    = "nocobase"
  content = var.public_wan_ip
  type    = "A"
  proxied = true
}