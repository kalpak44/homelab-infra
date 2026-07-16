data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "adguard" {
  zone_id = data.cloudflare_zone.this.id
  name    = "adguard.internal"
  content = "192.168.1.2"
  type    = "A"
  proxied = false
}