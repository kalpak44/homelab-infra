output "tunnel_token" {
  description = "Token passed to cloudflared on mihal-lxc via TUNNEL_TOKEN env var or service install"
  value       = cloudflare_zero_trust_tunnel_cloudflared.mihal.tunnel_token
  sensitive   = true
}
