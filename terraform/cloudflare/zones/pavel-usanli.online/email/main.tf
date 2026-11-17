data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

resource "cloudflare_email_routing_settings" "this" {
  zone_id = data.cloudflare_zone.this.id
  enabled = true
}

resource "cloudflare_email_routing_address" "destination" {
  account_id = data.cloudflare_zone.this.account_id
  email      = "pavel.usanli@gmail.com"
}

resource "cloudflare_email_routing_rule" "alias" {
  zone_id  = data.cloudflare_zone.this.id
  name     = "contact@pavel-usanli.online → pavel.usanli@gmail.com"
  enabled  = true
  priority = 1

  matcher {
    type  = "literal"
    field = "to"
    value = "contact@pavel-usanli.online"
  }

  action {
    type  = "forward"
    value = ["pavel.usanli@gmail.com"]
  }

  depends_on = [
    cloudflare_email_routing_settings.this,
    cloudflare_email_routing_address.destination,
  ]
}