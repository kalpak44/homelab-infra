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
