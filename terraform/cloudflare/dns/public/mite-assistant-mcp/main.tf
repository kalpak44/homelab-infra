data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "mite_assistant" {
  zone_id = data.cloudflare_zone.this.id
  name    = "mite-assistant"
  content = var.haproxy_public_ip
  type    = "A"
  proxied = true
}