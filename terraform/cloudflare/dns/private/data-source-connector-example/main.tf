data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_record" "data_source_connector_example" {
  zone_id = data.cloudflare_zone.this.id
  name    = "data-source-example.internal"
  content = "192.168.1.121"
  type    = "A"
  proxied = false
}