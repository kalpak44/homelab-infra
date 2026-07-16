data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "nocobase" {
  zone_id = data.cloudflare_zone.this.id
  name    = "nocobase"
  content = var.haproxy_public_ip
  type    = "A"
  proxied = true
}