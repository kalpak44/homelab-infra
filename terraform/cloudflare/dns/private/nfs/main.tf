data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "nfs" {
  zone_id = data.cloudflare_zone.this.id
  name    = "nfs.internal"
  content = "192.168.1.108"
  type    = "A"
  proxied = false
}