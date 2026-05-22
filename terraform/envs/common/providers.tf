provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_username}=${var.proxmox_password}"
  insecure  = true
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}