variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API username"
  type        = string
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key injected into the container via cloud-init"
  type        = string
  default     = ""
}

variable "ssh_private_key" {
  description = "SSH private key used by Terraform provisioners"
  type        = string
  sensitive   = true
  default     = ""
}

variable "lxc_template_file_id" {
  description = "Proxmox LXC template file ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
