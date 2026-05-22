variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_username" {
  type      = string
  sensitive = true
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type      = string
  sensitive = false
  default   = ""
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}