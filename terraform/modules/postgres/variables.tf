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