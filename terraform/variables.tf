variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL, e.g. https://192.168.1.50:8006/"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API username, e.g. root@pam"
  type        = string
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key injected into all provisioned VMs and containers via cloud-init"
  type        = string
  sensitive   = false
  default     = ""
}

variable "ssh_private_key" {
  description = "SSH private key used by Terraform provisioners to connect to VMs and containers"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit permissions for the managed zone"
  type        = string
  sensitive   = true
}

variable "haproxy_public_ip" {
  type        = string
  description = "Public IP address of the HAProxy load balancer (router WAN IP)"
  default     = ""
}