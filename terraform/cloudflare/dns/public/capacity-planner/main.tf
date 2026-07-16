data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "capacity_planner" {
  zone_id = data.cloudflare_zone.this.id
  name    = "planner"
  content = var.haproxy_public_ip
  type    = "A"
  proxied = true
}