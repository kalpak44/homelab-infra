data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "bunker_game_app" {
  zone_id = data.cloudflare_zone.this.id
  name    = "bunker"
  content = var.public_wan_ip
  type    = "A"
  proxied = true
}