variable "container_id" {
  description = "Proxmox container ID"
  type        = number
}

variable "ip_address" {
  description = "LAN IP address (without prefix), e.g. 192.168.1.115"
  type        = string
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.1.1"
}

variable "template_file_id" {
  description = "Proxmox LXC template file ID"
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject"
  type        = list(string)
  default     = []
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 1024
}

variable "disk_size_gb" {
  description = "Root disk size in GiB"
  type        = number
  default     = 8
}

variable "zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}