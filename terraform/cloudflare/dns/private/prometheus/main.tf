data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "prometheus" {
  zone_id = data.cloudflare_zone.this.id
  name    = "prometheus.internal"
  content = "192.168.1.11"
  type    = "A"
  proxied = false
}
