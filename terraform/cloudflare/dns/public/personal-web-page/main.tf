data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "apex" {
  zone_id = data.cloudflare_zone.this.id
  name    = "pavel-usanli.online"
  content = var.public_wan_ip
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.this.id
  name    = "www"
  content = "pavel-usanli.online"
  type    = "CNAME"
  proxied = true
}