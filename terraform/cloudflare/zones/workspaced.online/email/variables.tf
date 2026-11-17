variable "cloudflare_api_token" {
  description = "Cloudflare API token with Email Routing and DNS edit on the zone"
  type        = string
  sensitive   = true
}