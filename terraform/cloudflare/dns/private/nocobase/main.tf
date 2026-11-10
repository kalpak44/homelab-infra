data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "nocobase" {
  zone_id = data.cloudflare_zone.this.id
  name    = "nocobase.internal"
  content = "192.168.1.5"
  type    = "A"
  proxied = false
}
