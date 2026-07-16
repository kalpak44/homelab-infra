data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "traefik" {
  zone_id = data.cloudflare_zone.this.id
  name    = "traefik.internal"
  content = "192.168.1.121"
  type    = "A"
  proxied = false
}