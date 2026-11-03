data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "workspaced_ai" {
  zone_id = data.cloudflare_zone.this.id
  name    = "workspaced-ai.internal"
  content = "192.168.1.121"
  type    = "A"
  proxied = false
}
