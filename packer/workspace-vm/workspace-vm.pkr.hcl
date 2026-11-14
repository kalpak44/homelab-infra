# The OS every workspaced-ai VM boots from: Ubuntu with Docker installed and SSH masked,
# saved as a Hetzner snapshot in the VMs' own project. The VM manager is to pick the newest
# snapshot labelled image=workspace-vm.

packer {
  required_plugins {
    hcloud = {
      source  = "github.com/hetznercloud/hcloud"
      version = "= 1.8.2"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

# Where the VMs run; a snapshot built elsewhere would be copied across on every create.
variable "location" {
  type    = string
  default = "nbg1"
}

locals {
  stamp = formatdate("YYYYMMDD-hhmm", timestamp())
}

source "hcloud" "workspace_vm" {
  token       = var.hcloud_token
  image       = "ubuntu-24.04"
  location    = var.location
  server_type = "cx23"
  server_name = "packer-workspace-vm-${local.stamp}"
  # Not managed-by=workspaced-ai-vm-manager, so the VM manager never adopts the build server
  # into its inventory.
  server_labels = {
    managed-by = "packer"
  }
  ssh_username  = "root"
  snapshot_name = "workspace-vm-${local.stamp}"
  snapshot_labels = {
    image    = "workspace-vm"
    built-at = local.stamp
  }
}

build {
  sources = ["source.hcloud.workspace_vm"]

  provisioner "shell" {
    script = "${path.root}/setup.sh"
  }
}
