data "cloudflare_zone" "workspaced" {
  name = "workspaced.online"
}

# Users sign in on our own domain. Auth0 issues the certificate, which is why the record
# stays DNS-only: a proxied one answers with Cloudflare's certificate instead.
# Recreating it would change the issuer every token and the API are set to.
resource "auth0_custom_domain" "this" {
  domain = "auth.workspaced.online"
  type   = "auth0_managed_certs"

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_record" "auth" {
  zone_id = data.cloudflare_zone.workspaced.id
  name    = "auth"
  type    = "CNAME"
  content = auth0_custom_domain.this.verification[0].methods[0].record
  proxied = false
}

resource "auth0_custom_domain_verification" "this" {
  custom_domain_id = auth0_custom_domain.this.id

  timeouts {
    create = "15m"
  }

  depends_on = [cloudflare_record.auth]
}
