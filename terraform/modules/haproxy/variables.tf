variable "zone_id" {
  type = string
}

variable "template_file_id" {
  type = string
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "container_id" {
  type    = number
  default = 300
}

variable "ip_address" {
  type    = string
  default = "192.168.1.109"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "cpu_cores" {
  type    = number
  default = 1
}

variable "memory_mb" {
  type    = number
  default = 512
}

variable "disk_size_gb" {
  type    = number
  default = 8
}