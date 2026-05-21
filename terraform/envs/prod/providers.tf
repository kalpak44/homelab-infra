provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_username}=${var.proxmox_password}"
  insecure  = true

  ssh {
    username    = "root"
    private_key = var.proxmox_ssh_private_key
  }
}

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

variable "proxmox_ssh_private_key" {
  type      = string
  sensitive = true
  default   = ""
}