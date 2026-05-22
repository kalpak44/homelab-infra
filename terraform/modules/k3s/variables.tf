variable "template_vm_id" {
  description = "VM ID of the Ubuntu cloud-init template to clone for k3s nodes"
  type        = number
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}

variable "node1_id" {
  description = "Proxmox VM ID for k3s-1 (control plane)"
  type        = number
  default     = 110
}

variable "node1_ip" {
  description = "Static IPv4 address for k3s-1 (control plane), without CIDR prefix"
  type        = string
  default     = "192.168.1.110"
}

variable "node2_id" {
  description = "Proxmox VM ID for k3s-2 (worker)"
  type        = number
  default     = 111
}

variable "node2_ip" {
  description = "Static IPv4 address for k3s-2 (worker), without CIDR prefix"
  type        = string
  default     = "192.168.1.111"
}

variable "gateway" {
  description = "Default gateway for k3s node network interfaces"
  type        = string
  default     = "192.168.1.1"
}

variable "cpu_cores" {
  description = "Number of vCPU cores allocated to each k3s node"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM in MiB allocated to each k3s node"
  type        = number
  default     = 8192
}

variable "disk_size_gb" {
  description = "Root disk size in GiB for each k3s node"
  type        = number
  default     = 40
}