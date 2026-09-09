# Apex to www, answered at Cloudflare's edge so the request never crosses the tunnel.
#
# The apex keeps its proxied CNAME in main.tf: the redirect only fires because Cloudflare
# is in front of it, so removing that record would stop the apex resolving at all. Its
# tunnel ingress rule is now unreachable, because a dynamic redirect is answered before
# an origin is chosen.
#
# One entrypoint per phase, and writing it replaces the whole rule list — the same hazard
# as edge-ports.tf. Nothing else used this phase on this zone, so there was nothing to
# import; a second redirect belongs in this ruleset rather than in a resource of its own.
resource "cloudflare_ruleset" "redirects" {
  zone_id = data.cloudflare_zone.this.id
  # Cloudflare names a phase entrypoint "default" and rewrites anything else.
  name  = "default"
  kind  = "zone"
  phase = "http_request_dynamic_redirect"

  rules {
    ref         = "apex_to_www"
    action      = "redirect"
    description = "Apex to www"
    enabled     = true

    # Scheme-independent: this matches the plain-HTTP request too, and the absolute
    # https target below lands it on www in one hop instead of bouncing through
    # always_use_https first.
    expression = "(http.host eq \"pavel-usanli.online\")"

    action_parameters {
      from_value {
        status_code = 301

        # The path is carried by the expression, the query string by the flag below —
        # appending http.request.uri instead would duplicate the query.
        target_url {
          expression = "concat(\"https://www.pavel-usanli.online\", http.request.uri.path)"
        }

        preserve_query_string = true
      }
    }
  }
}
