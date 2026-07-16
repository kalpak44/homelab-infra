variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit permissions"
  type        = string
  sensitive   = true
}

variable "public_wan_ip" {
  description = "Public WAN IP address for internet-facing DNS records"
  type        = string
}