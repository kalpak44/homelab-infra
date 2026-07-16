data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "redis" {
  zone_id = data.cloudflare_zone.this.id
  name    = "redis.internal"
  content = "192.168.1.6"
  type    = "A"
  proxied = false
}