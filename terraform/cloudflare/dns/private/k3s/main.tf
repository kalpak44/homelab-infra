data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "k3s_1" {
  zone_id = data.cloudflare_zone.this.id
  name    = "k3s-1.internal"
  content = "192.168.1.110"
  type    = "A"
  proxied = false
}

resource "cloudflare_record" "k3s_2" {
  zone_id = data.cloudflare_zone.this.id
  name    = "k3s-2.internal"
  content = "192.168.1.111"
  type    = "A"
  proxied = false
}
