variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit on workspaced.online"
  type        = string
  sensitive   = true
}

# An empty key would be written to Auth0 as-is and break verification and reset mail.
variable "mailjet_api_key_public" {
  description = "Mailjet API key, the SMTP username"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mailjet_api_key_public) > 0
    error_message = "MJ_APIKEY_PUBLIC is empty in this shell."
  }
}

variable "mailjet_api_key_private" {
  description = "Mailjet secret key, the SMTP password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mailjet_api_key_private) > 0
    error_message = "MJ_APIKEY_PRIVATE is empty in this shell."
  }
}
