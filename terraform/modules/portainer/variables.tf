variable "zone_id" {
  description = "Cloudflare zone ID used to create the portainer.internal DNS A record"
  type        = string
}

variable "template_vm_id" {
  description = "Proxmox VM ID of the Ubuntu template to clone from"
  type        = number
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}

variable "vm_id" {
  description = "Proxmox VM ID for the Portainer instance"
  type        = number
  default     = 302
}

variable "ip_address" {
  description = "Static IPv4 address without CIDR prefix; /24 is appended automatically"
  type        = string
  default     = "192.168.1.7"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.1.1"
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 1
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 1024
}

variable "disk_size_gb" {
  description = "Root disk size in GiB"
  type        = number
  default     = 10
}