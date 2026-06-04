variable "zone_id" {
  description = "Cloudflare zone ID for pavel-usanli.online"
  type        = string
}

variable "account_id" {
  description = "Cloudflare account ID (used to register the destination address)"
  type        = string
}

variable "alias_name" {
  description = "Local part of the alias address, e.g. 'contact' → contact@pavel-usanli.online"
  type        = string
  default     = "contact"
}

variable "domain" {
  description = "Domain for the alias address"
  type        = string
  default     = "pavel-usanli.online"
}

variable "destination_email" {
  description = "Gmail address that receives all forwarded mail"
  type        = string
  default     = "pavel.usanli@gmail.com"
}