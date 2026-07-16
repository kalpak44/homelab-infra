data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "haproxy" {
  zone_id = data.cloudflare_zone.this.id
  name    = "haproxy.internal"
  content = "192.168.1.109"
  type    = "A"
  proxied = false
}