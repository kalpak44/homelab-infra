# Cloudflare's edge answers on more ports than 80 and 443.
resource "cloudflare_ruleset" "edge_ports" {
  zone_id     = data.cloudflare_zone.this.id
  name        = "edge-ports"
  description = "Serve this zone on 80 and 443 only"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    ref         = "block_non_standard_edge_ports"
    action      = "block"
    description = "Block HTTP(S) on Cloudflare's alternate proxied ports"
    enabled     = true

    # cf.edge.server_port is the port the Cloudflare network accepted the request
    # on, not the origin port — which is the only place the distinction exists.
    expression = "not (cf.edge.server_port in {80 443})"
  }
}