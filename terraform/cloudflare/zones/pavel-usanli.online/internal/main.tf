data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

# LAN-only names, resolved by AdGuard from these unproxied records. key = the label before
# .internal, value = the host's LAN address; 192.168.1.121 is Traefik's MetalLB address.
locals {
  internal_records = {
    "acestream"     = "192.168.1.7"
    "adguard"       = "192.168.1.2"
    "cloudflared"   = "192.168.1.10"
    "crowdsec"      = "192.168.1.121"
    "github-runner" = "192.168.1.101"
    "grafana"       = "192.168.1.12"
    "headlamp"      = "192.168.1.121"
    "home"          = "192.168.1.121"
    "k3s-1"         = "192.168.1.110"
    "k3s-2"         = "192.168.1.111"
    "mihal"         = "192.168.1.9"
    "nfs"           = "192.168.1.108"
    "nocobase"      = "192.168.1.5"
    "pgadmin"       = "192.168.1.4"
    "portainer"     = "192.168.1.7"
    "postgres"      = "192.168.1.4"
    "prometheus"    = "192.168.1.11"
    "proxmox"       = "192.168.1.50"
    "redis"         = "192.168.1.6"
    "rustfs"        = "192.168.1.13"
    "songradar"     = "192.168.1.121"
    "traefik"       = "192.168.1.121"
    "vault"         = "192.168.1.3"
  }
}

resource "cloudflare_record" "internal" {
  for_each = local.internal_records

  zone_id = data.cloudflare_zone.this.id
  name    = "${each.key}.internal"
  content = each.value
  type    = "A"
  proxied = false
}
