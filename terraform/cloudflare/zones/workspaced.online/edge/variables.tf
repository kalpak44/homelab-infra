variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:WAF:Edit, Zone Settings:Edit and DNS:Edit"
  type        = string
  sensitive   = true
}
