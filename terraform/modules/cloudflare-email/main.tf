resource "cloudflare_email_routing_settings" "this" {
  zone_id = var.zone_id
  enabled = true
}

# Registers the destination address and triggers a one-time verification email to that inbox.
# Routing will not activate until the link in that email is clicked.
resource "cloudflare_email_routing_address" "destination" {
  account_id = var.account_id
  email      = var.destination_email
}

resource "cloudflare_email_routing_rule" "alias" {
  zone_id  = var.zone_id
  name     = "${var.alias_name}@${var.domain} → ${var.destination_email}"
  enabled  = true
  priority = 1

  matcher {
    type  = "literal"
    field = "to"
    value = "${var.alias_name}@${var.domain}"
  }

  action {
    type  = "forward"
    value = [var.destination_email]
  }

  depends_on = [
    cloudflare_email_routing_settings.this,
    cloudflare_email_routing_address.destination,
  ]
}