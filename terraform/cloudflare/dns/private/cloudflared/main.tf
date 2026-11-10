data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "cloudflared" {
  zone_id = data.cloudflare_zone.this.id
  name    = "cloudflared.internal"
  content = "192.168.1.10"
  type    = "A"
  proxied = false
}
