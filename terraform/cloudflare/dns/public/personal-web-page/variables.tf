variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit permissions"
  type        = string
  sensitive   = true
}

variable "haproxy_public_ip" {
  description = "Public IP address of the HAProxy load balancer"
  type        = string
}