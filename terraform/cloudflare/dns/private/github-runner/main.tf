data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "github_runner" {
  zone_id = data.cloudflare_zone.this.id
  name    = "github-runner.internal"
  content = "192.168.1.101"
  type    = "A"
  proxied = false
}
