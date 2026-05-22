module "haproxy" {
  source           = "./modules/haproxy"
  zone_id          = data.cloudflare_zone.this.id
  template_file_id = proxmox_download_file.ubuntu_lxc.id
  ssh_public_keys  = [var.ssh_public_key]
}