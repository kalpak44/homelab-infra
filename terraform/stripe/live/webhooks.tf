import {
  to = stripe_webhook_endpoint.workspaced_billing
  id = "we_1UcArPABYXXbGldTOhEnkb4b"
}

# Stripe returns the signing secret only when an endpoint is created, so a replacement
# breaks billing until stripe-webhook-secret in secret/workspaced-secrets is updated.
resource "stripe_webhook_endpoint" "workspaced_billing" {
  url         = "https://ai.workspaced.online/api/v1/billing/stripe/webhook"
  description = "Webhook endpoint"
  api_version = "2020-08-27"

  enabled_events = [
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
    "checkout.session.async_payment_failed",
    "checkout.session.expired",
  ]

  lifecycle {
    prevent_destroy = true
  }
}
