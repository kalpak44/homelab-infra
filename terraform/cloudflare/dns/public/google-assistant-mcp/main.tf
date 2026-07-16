data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "google_assistant" {
  zone_id = data.cloudflare_zone.this.id
  name    = "google-assistant"
  content = var.public_wan_ip
  type    = "A"
  proxied = true
}