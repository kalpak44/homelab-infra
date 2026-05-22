variable "zone_id" {
  description = "Cloudflare zone ID used to create the postgres.internal and pgadmin.internal DNS A records"
  type        = string
}

variable "template_file_id" {
  description = "Proxmox LXC template file ID for the Ubuntu container image"
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject into the container"
  type        = list(string)
  default     = []
}

variable "container_id" {
  description = "Proxmox container ID for the PostgreSQL instance"
  type        = number
  default     = 202
}

variable "ip_address" {
  description = "Static IPv4 address without CIDR prefix; /24 is appended automatically"
  type        = string
  default     = "192.168.1.4"
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
  default     = 2048
}

variable "disk_size_gb" {
  description = "Root disk size in GiB"
  type        = number
  default     = 16
}