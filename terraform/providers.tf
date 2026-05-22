provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_username}=${var.proxmox_password}"
  insecure  = true

  ssh {
    username    = "root"
    private_key = var.ssh_private_key
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}