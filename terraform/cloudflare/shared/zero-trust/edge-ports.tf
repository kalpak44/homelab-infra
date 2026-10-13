# The zone's one WAF custom ruleset. Cloudflare allows exactly one entrypoint per
# phase, and writing it REPLACES the whole rule list — same hazard as the tunnel
# ingress config, so a rule added in the dashboard is deleted by the next apply here.
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

  # Never add a `skip` carrying `ruleset = "current"` above a rule meant to run. One
  # matching `http.user_agent wildcard "*"` sat here and matched every request, so
  # every rule below it was dead on arrival and a new rule would be too.
  #
  # A js_challenge on mite-assistant.pavel-usanli.online went with it: MCP clients
  # execute no JavaScript, so any challenge on that hostname takes the server off the
  # air. Exempt it from challenge and bot-score rules alike.
  rules {
    ref         = "block_non_standard_edge_ports"
    action      = "block"
    description = "Block HTTP(S) on Cloudflare's alternate proxied ports"
    enabled     = true

    # cf.edge.server_port is the port Cloudflare accepted the request on, not the
    # origin port — the only place the distinction exists.
    expression = "not (cf.edge.server_port in {80 443})"
  }
}
