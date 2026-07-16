data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "rabbitmq" {
  zone_id = data.cloudflare_zone.this.id
  name    = "rabbitmq.internal"
  content = "192.168.1.8"
  type    = "A"
  proxied = false
}