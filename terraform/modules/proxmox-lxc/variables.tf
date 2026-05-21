variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "container_id" {
  description = "Proxmox container ID"
  type        = number
}

variable "hostname" {
  description = "Container hostname"
  type        = string
}

variable "template_file_id" {
  description = "Proxmox template file ID, e.g. local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  type        = string
}

variable "ip_address" {
  description = "Static IPv4 in CIDR notation, e.g. 192.168.1.2/24"
  type        = string
}

variable "gateway" {
  description = "Default gateway"
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
  default     = 1
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 256
}

variable "disk_size_gb" {
  description = "Root disk size in GiB"
  type        = number
  default     = 4
}

variable "datastore_id" {
  description = "Proxmox datastore"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox bridge interface"
  type        = string
  default     = "vmbr0"
}

variable "unprivileged" {
  description = "Run as unprivileged container"
  type        = bool
  default     = true
}