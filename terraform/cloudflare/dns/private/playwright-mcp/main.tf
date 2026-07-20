data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "playwright_mcp" {
  zone_id = data.cloudflare_zone.this.id
  name    = "playwright-mcp.internal"
  content = "192.168.1.121"
  type    = "A"
  proxied = false
}