variable "zone_id" {
  type = string
}

variable "template_vm_id" {
  type = number
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "vm_id" {
  type    = number
  default = 301
}

variable "ip_address" {
  type    = string
  default = "192.168.1.108"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "data_disk_size_gb" {
  type    = number
  default = 512
}