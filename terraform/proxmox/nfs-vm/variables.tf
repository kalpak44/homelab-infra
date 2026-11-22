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
  description = "SSH public key injected into the VM via cloud-init"
  type        = string
  default     = ""
}

variable "ssh_private_key" {
  description = "SSH private key used by Terraform provisioners"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vm_template_id" {
  description = "Proxmox VM ID of the Ubuntu template to clone from"
  type        = number
  default     = 9000
}
