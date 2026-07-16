data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "crowdsec_web_ui" {
  zone_id = data.cloudflare_zone.this.id
  name    = "crowdsec.internal"
  content = "192.168.1.121"
  type    = "A"
  proxied = false
}