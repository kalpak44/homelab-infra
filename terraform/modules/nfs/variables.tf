variable "zone_id" {
  description = "Cloudflare zone ID used to create the nfs.internal DNS A record"
  type        = string
}

variable "template_vm_id" {
  description = "VM ID of the Ubuntu cloud-init template to clone"
  type        = number
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}

variable "vm_id" {
  description = "Proxmox VM ID for the NFS server"
  type        = number
  default     = 301
}

variable "ip_address" {
  description = "Static IPv4 address without CIDR prefix; /24 is appended automatically"
  type        = string
  default     = "192.168.1.108"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.1.1"
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
  description = "OS disk size in GiB"
  type        = number
  default     = 20
}

variable "data_disk_size_gb" {
  description = "NFS data disk size in GiB, mounted at /srv/nfs"
  type        = number
  default     = 512
}