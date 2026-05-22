variable "template_vm_id" {
  type = number
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "node1_id" {
  type    = number
  default = 110
}

variable "node1_ip" {
  type    = string
  default = "192.168.1.110"
}

variable "node2_id" {
  type    = number
  default = 111
}

variable "node2_ip" {
  type    = string
  default = "192.168.1.111"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "cpu_cores" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_size_gb" {
  type    = number
  default = 40
}