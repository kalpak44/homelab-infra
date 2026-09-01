output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "tunnel_cname" {
  description = "CNAME target for public DNS records pointing at the tunnel"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
}

output "tunnel_token" {
  description = "Token passed to cloudflared via TUNNEL_TOKEN env var or service install"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab.tunnel_token
  sensitive   = true
}

output "warp_service_token_client_id" {
  description = "CF_WARP_CLIENT_ID for the deepcraft-nocobase workflow"
  value       = cloudflare_zero_trust_access_service_token.nocobase_ci.client_id
}

output "warp_service_token_client_secret" {
  description = "CF_WARP_CLIENT_SECRET for the deepcraft-nocobase workflow"
  value       = cloudflare_zero_trust_access_service_token.nocobase_ci.client_secret
  sensitive   = true
}