data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "mihal" {
  zone_id = data.cloudflare_zone.this.id
  name    = "mihal.internal"
  content = "192.168.1.9"
  type    = "A"
  proxied = false
}
