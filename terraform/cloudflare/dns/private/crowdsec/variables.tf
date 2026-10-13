variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit permissions"
  type        = string
  sensitive   = true
}