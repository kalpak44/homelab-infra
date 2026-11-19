# Auth0's built-in mail is rate-limited and meant for testing, so verification and reset
# mail goes out through the Mailjet account the domain already sends with.
resource "auth0_email_provider" "mailjet" {
  name                 = "smtp"
  enabled              = true
  default_from_address = "noreply@workspaced.online"

  credentials {
    smtp_host = "in-v3.mailjet.com"
    smtp_port = 587
    smtp_user = var.mailjet_api_key_public
    smtp_pass = var.mailjet_api_key_private
  }
}

locals {
  email_templates = {
    verify_email = "Verify your email for workspaced"
    reset_email  = "Reset your workspaced password"
  }
}

# The app's own mail layout around Auth0's two messages, so all mail from the domain looks alike.
resource "auth0_email_template" "this" {
  for_each = local.email_templates

  template                = each.key
  enabled                 = true
  from                    = "workspaced <noreply@workspaced.online>"
  subject                 = each.value
  syntax                  = "liquid"
  url_lifetime_in_seconds = 432000

  body = templatefile("${path.module}/mail/layout.html.tftpl", {
    title   = each.value
    content = file("${path.module}/mail/${each.key}.html")
  })

  depends_on = [auth0_email_provider.mailjet]
}
