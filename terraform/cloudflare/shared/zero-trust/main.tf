data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

# Second public zone on the same tunnel. Registered at GoDaddy, nameservers
# delegated to Cloudflare — GoDaddy is registrar and billing only.
data "cloudflare_zone" "proklinator" {
  name = "proklinator.online"
}

resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = data.cloudflare_zone.this.account_id
  name       = "k3s"
  secret     = random_bytes.tunnel_secret.base64
}

locals {
  # key = record name, value = hostname for ingress rule
  public_k3s_apps = {
    "pavel-usanli.online"   = "pavel-usanli.online"
    "www"                   = "www.pavel-usanli.online"
    "nocobase"              = "nocobase.pavel-usanli.online"
    "planner"               = "planner.pavel-usanli.online"
    "bunker"                = "bunker.pavel-usanli.online"
    "mite-assistant"        = "mite-assistant.pavel-usanli.online"
    "google-assistant"      = "google-assistant.pavel-usanli.online"
    "shopify-gpt-assistant" = "shopify-gpt-assistant.pavel-usanli.online"
    "noco-ai-tools"         = "noco-ai-tools.pavel-usanli.online"
  }

  proklinator_apps = {
    "proklinator.online" = "proklinator.online"
    "www"                = "www.proklinator.online"
  }

  # Ingress rules are keyed by hostname, not record name, so "www" existing in
  # both zones doesn't collide. Cloudflare-for-SaaS hostnames belong here too:
  # we hold no DNS record for them, but the tunnel still has to recognise the
  # Host header they arrive with. See saas.tf.
  all_hostnames = toset(concat(
    values(local.public_k3s_apps),
    values(local.proklinator_apps),
    keys(local.saas_customers),
  ))

  # Every hostname reaches Traefik in k3s unless it appears in ingress_overrides.
  # An override sends one hostname straight at a box on the LAN instead, which
  # also means it bypasses Traefik — so no cert-manager, and no CrowdSec.
  traefik_origin = "https://192.168.1.120"

  # Currently only the SaaS customers, which reach nginx on nocobase-lxc over
  # plain HTTP: Cloudflare terminates TLS at the edge and cloudflared crosses
  # the LAN, so that box needs no certificate and never listens on 443.
  ingress_overrides = local.saas_customers

  ingress_services = {
    for h in local.all_hostnames : h => lookup(local.ingress_overrides, h, local.traefik_origin)
  }

  tunnel_cname = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
}

resource "cloudflare_record" "public" {
  for_each = local.public_k3s_apps

  zone_id = data.cloudflare_zone.this.id
  name    = each.key
  content = local.tunnel_cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "proklinator" {
  for_each = local.proklinator_apps

  zone_id = data.cloudflare_zone.proklinator.id
  name    = each.key
  content = local.tunnel_cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = data.cloudflare_zone.this.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config {
    # Required by the private network route in warp.tf. Cloudflare turns this on
    # by itself when a route is added, so leaving it undeclared means every apply
    # of this dir plans to switch WARP routing back off and silently break it.
    warp_routing {
      enabled = true
    }

    dynamic "ingress_rule" {
      for_each = local.ingress_services
      content {
        hostname = ingress_rule.key
        service  = ingress_rule.value
        origin_request {
          # Only meaningful for the https origins; ignored for plain http ones.
          no_tls_verify = true
        }
      }
    }

    # catch-all required by Cloudflare
    ingress_rule {
      service = "http_status:404"
    }
  }
}