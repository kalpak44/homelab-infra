data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "rustfs" {
  zone_id = data.cloudflare_zone.this.id
  name    = "rustfs.internal"
  content = "192.168.1.13"
  type    = "A"
  proxied = false
}
