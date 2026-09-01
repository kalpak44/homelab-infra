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

output "saas_fallback_origin" {
  description = "CNAME target every Cloudflare-for-SaaS customer points their hostname at"
  value       = local.saas_fallback_origin
}

# Everything a customer has to add at their own DNS provider. The two validation
# records are computed by Cloudflare and can still be empty on the apply that
# created the custom hostname — re-read this output after a refresh.
output "saas_customer_onboarding" {
  description = "Per-customer records to hand over, plus current certificate status"
  value = {
    for host, ch in cloudflare_custom_hostname.customer : host => {
      cname                 = { name = host, type = "CNAME", value = local.saas_fallback_origin }
      ownership_validation  = ch.ownership_verification
      certificate_validation = ch.ssl[0].validation_records
      status                = ch.status
    }
  }
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