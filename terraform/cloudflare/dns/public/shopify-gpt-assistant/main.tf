data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "shopify_gpt_assistant" {
  zone_id = data.cloudflare_zone.this.id
  name    = "shopify-gpt-assistant"
  content = var.public_wan_ip
  type    = "A"
  proxied = true
}