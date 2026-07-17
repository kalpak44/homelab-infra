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