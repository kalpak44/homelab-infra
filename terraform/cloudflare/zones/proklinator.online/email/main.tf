data "cloudflare_zone" "this" {
  name = "proklinator.online"
}

# Enabling routing makes Cloudflare create the zone's MX and SPF records itself.
resource "cloudflare_email_routing_settings" "this" {
  zone_id = data.cloudflare_zone.this.id
  enabled = true
}

# The destination is an account-level address, verified and managed in
# zones/pavel-usanli.online/email; declaring it here too would put it in two states.
resource "cloudflare_email_routing_rule" "sales" {
  zone_id  = data.cloudflare_zone.this.id
  name     = "sales@proklinator.online → pavel.usanli@gmail.com"
  enabled  = true
  priority = 1

  matcher {
    type  = "literal"
    field = "to"
    value = "sales@proklinator.online"
  }

  action {
    type  = "forward"
    value = ["pavel.usanli@gmail.com"]
  }

  depends_on = [cloudflare_email_routing_settings.this]
}
