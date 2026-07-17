data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
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

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = data.cloudflare_zone.this.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config {
    dynamic "ingress_rule" {
      for_each = local.public_k3s_apps
      content {
        hostname = ingress_rule.value
        service  = "https://192.168.1.120"
        origin_request {
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