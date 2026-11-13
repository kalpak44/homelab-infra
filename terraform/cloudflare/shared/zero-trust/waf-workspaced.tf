# Destroying this resource reverts every zone setting to its pre-apply value, not just
# the one named here.
resource "cloudflare_zone_settings_override" "workspaced" {
  zone_id = data.cloudflare_zone.workspaced.id

  settings {
    # Off, the edge serves the login form and session over cleartext HTTP; Traefik only
    # sees the tunnel's encrypted leg, so nothing behind it can tell. Covers the
    # alternate HTTP ports too; their HTTPS twins are the ruleset below.
    always_use_https = "on"
  }
}

# The workspaced zone's one WAF custom ruleset. Cloudflare allows a single entrypoint per
# phase and writing it REPLACES the whole rule list, so every custom rule for this zone
# belongs here — one added in the dashboard is deleted by the next apply.
resource "cloudflare_ruleset" "workspaced" {
  zone_id = data.cloudflare_zone.workspaced.id
  # Cloudflare names a phase entrypoint "default" and rewrites anything else.
  name  = "default"
  kind  = "zone"
  phase = "http_request_firewall_custom"

  rules {
    ref         = "block_non_standard_edge_ports"
    action      = "block"
    description = "Block HTTP(S) on Cloudflare's alternate proxied ports"
    enabled     = true

    expression = "not (cf.edge.server_port in {80 443})"
  }

  # Omitted entirely while the list is empty: Cloudflare rejects `ip.src in {}`. The list
  # is in waf-blocked-ips.tf.
  dynamic "rules" {
    for_each = length(local.blocked_ips) > 0 ? [1] : []
    content {
      ref         = "block_reviewed_abusive_ips"
      action      = "block"
      description = "Block addresses on the reviewed blocklist"
      enabled     = true

      expression = local.blocked_ips_expression
    }
  }
}
