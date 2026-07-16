data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "postgres" {
  zone_id = data.cloudflare_zone.this.id
  name    = "postgres.internal"
  content = "192.168.1.4"
  type    = "A"
  proxied = false
}

resource "cloudflare_record" "pgadmin" {
  zone_id = data.cloudflare_zone.this.id
  name    = "pgadmin.internal"
  content = "192.168.1.4"
  type    = "A"
  proxied = false
}