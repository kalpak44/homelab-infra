data "cloudflare_zone" "this" {
  name = "workspaced.online"
}

# Enabling routing makes Cloudflare create the zone's MX records and its first SPF record,
# which mailjet.tf has since adopted.
resource "cloudflare_email_routing_settings" "this" {
  zone_id = data.cloudflare_zone.this.id
  enabled = true
}

# The destination is an account-level address, verified and managed in
# zones/pavel-usanli.online/email; declaring it here too would put it in two states.
resource "cloudflare_email_routing_rule" "forward" {
  for_each = toset(["sales", "support", "investor"])

  zone_id  = data.cloudflare_zone.this.id
  name     = "${each.key}@workspaced.online → pavel.usanli@gmail.com"
  enabled  = true
  priority = 1

  matcher {
    type  = "literal"
    field = "to"
    value = "${each.key}@workspaced.online"
  }

  action {
    type  = "forward"
    value = ["pavel.usanli@gmail.com"]
  }

  depends_on = [cloudflare_email_routing_settings.this]
}

# The sales rule predates the map; moving it keeps its rule id instead of recreating it.
moved {
  from = cloudflare_email_routing_rule.sales
  to   = cloudflare_email_routing_rule.forward["sales"]
}
