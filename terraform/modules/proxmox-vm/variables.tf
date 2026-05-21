variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_name" {
  description = "VM hostname"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID (100–999999)"
  type        = number
}

variable "cloud_image_file_id" {
  description = "Proxmox file ID of the cloud image to use as the root disk"
  type        = string
}

variable "cpu_cores" {
  description = "Number of vCPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Root disk size in GiB"
  type        = number
  default     = 20
}

variable "datastore_id" {
  description = "Proxmox datastore for the disk"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox bridge interface"
  type        = string
  default     = "vmbr0"
}

variable "ip_address" {
  description = "Static IPv4 in CIDR notation, e.g. 192.168.1.10/24"
  type        = string
}

variable "gateway" {
  description = "Default gateway"
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}