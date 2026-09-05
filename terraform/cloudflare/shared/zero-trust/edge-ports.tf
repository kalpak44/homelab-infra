# The zone's one WAF custom ruleset. Cloudflare allows exactly one entrypoint per
# phase, and writing it REPLACES the whole rule list — same hazard as the tunnel
# ingress config. The two dashboard-made rules below are therefore restated here,
# not because this dir wants to own them, but because omitting them deletes them.
import {
  to = cloudflare_ruleset.edge_ports
  id = "zone/e6d8e2575b878bbc1e52039d45c87e0e/8d662ce891274a2a8155904ee4ebe74e"
}

resource "cloudflare_ruleset" "edge_ports" {
  zone_id = data.cloudflare_zone.this.id
  # Cloudflare names a phase entrypoint "default" and rewrites anything else.
  name  = "default"
  kind  = "zone"
  phase = "http_request_firewall_custom"

  # Order is load-bearing. The "general" rule below skips the rest of this ruleset
  # and its expression matches every request, so anything under it never runs —
  # which is why this one is first and why the js_challenge is already dead.
  rules {
    ref         = "block_non_standard_edge_ports"
    action      = "block"
    description = "Block HTTP(S) on Cloudflare's alternate proxied ports"
    enabled     = true

    # cf.edge.server_port is the port Cloudflare accepted the request on, not the
    # origin port — the only place the distinction exists.
    expression = "not (cf.edge.server_port in {80 443})"
  }

  # Pre-existing, made in the dashboard. Restated verbatim; behaviour unchanged.
  rules {
    ref         = "b38c0035858840e8bcbb0e3241bc6e68"
    action      = "skip"
    description = "general"
    enabled     = true
    expression  = "(http.user_agent wildcard r\"*\")"

    action_parameters {
      ruleset = "current"
    }

    logging {
      enabled = true
    }
  }

  # Pre-existing, and unreachable behind the skip above. Kept as found.
  rules {
    ref         = "ce6573d64b0b4d7fb59f8a090362fb71"
    action      = "js_challenge"
    description = "no_chalenge"
    enabled     = true
    expression  = "(http.host contains \"mite-assistant.pavel-usanli.online\") or (http.host contains \"nocobase.pavel-usanli.online\") or (http.host contains \"noco-ai-tools.pavel-usanli.online\")"
  }
}
