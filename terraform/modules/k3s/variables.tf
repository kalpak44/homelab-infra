variable "template_vm_id" {
  type = number
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}