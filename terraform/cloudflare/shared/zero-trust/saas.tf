# Cloudflare for SaaS — serving hostnames on domains we do not host.
#
# A customer CNAMEs their hostname at us. It resolves to our edge IPs but the
# handshake arrives with *their* SNI, which the edge has no zone to match it
# against and rejects outright (1016) — a plain CNAME is not enough on its own.
# A custom hostname registers that SNI against our zone and issues a DV
# certificate for it, after which the request is routed to the fallback origin
# with the Host header left untouched.
#
# Untouched is the operative word: cloudflared matches ingress on Host, so every
# entry in saas_customers also needs an ingress rule, which is why main.tf folds
# this map into ingress_overrides. Skip that and the handshake succeeds and the
# request lands on the catch-all 404 — indistinguishable from a DNS mistake.

locals {
  # key = the customer's hostname, value = the origin it should reach.
  saas_customers = {
    # Simulated customer. proklinator.online is a zone in this same account, so
    # its `app` record has to stay DNS-only for the simulation to be honest —
    # an orange-clouded record is handled by that zone's own proxy and never
    # reaches the custom-hostname path at all.
    "app.proklinator.online" = "http://192.168.1.5:80"
  }

  saas_fallback_origin = "saas.pavel-usanli.online"
}

# Every custom hostname routes here. A dedicated record rather than reusing
# deepcraft-nocobase: the fallback origin is an edge routing target, and pointing
# it at a name that also serves its own traffic conflates the two. It is
# deliberately left out of all_hostnames, so hitting it directly gets the
# catch-all 404 rather than quietly becoming a second public entrance.
resource "cloudflare_record" "saas_fallback" {
  zone_id = data.cloudflare_zone.this.id
  name    = "saas"
  content = local.tunnel_cname
  type    = "CNAME"
  proxied = true
}

# Cloudflare rejects a fallback origin whose record does not exist yet, and it
# has no reference to the record to infer the ordering from.
resource "cloudflare_custom_hostname_fallback_origin" "this" {
  zone_id = data.cloudflare_zone.this.id
  origin  = local.saas_fallback_origin

  depends_on = [cloudflare_record.saas_fallback]
}

resource "cloudflare_custom_hostname" "customer" {
  for_each = local.saas_customers

  zone_id  = data.cloudflare_zone.this.id
  hostname = each.key

  ssl {
    # TXT validation, not HTTP. HTTP validation needs the customer's CNAME to be
    # serving already, and on a hostname that is not yet live that is circular.
    # TXT lets them prepare every record in one pass before cutting traffic over.
    method                = "txt"
    type                  = "dv"
    certificate_authority = "google"
    bundle_method         = "ubiquitous"

    settings {
      min_tls_version = "1.2"
    }
  }

  # The customer cannot have added the validation records by the time this
  # applies, so waiting here would only block the apply until it timed out.
  # Issuance is asynchronous; `status` on the next refresh is what to watch.
  wait_for_ssl_pending_validation = false

  depends_on = [cloudflare_custom_hostname_fallback_origin.this]
}