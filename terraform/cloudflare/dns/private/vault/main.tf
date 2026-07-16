data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "vault" {
  zone_id = data.cloudflare_zone.this.id
  name    = "vault.internal"
  content = "192.168.1.3"
  type    = "A"
  proxied = false
}