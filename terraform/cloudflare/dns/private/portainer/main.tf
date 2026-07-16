data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "portainer" {
  zone_id = data.cloudflare_zone.this.id
  name    = "portainer.internal"
  content = "192.168.1.7"
  type    = "A"
  proxied = false
}