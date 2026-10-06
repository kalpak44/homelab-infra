# ─── Dedicated WARP tunnel to mihal-lxc ───────────────────────────────────────
#
# A separate Cloudflare Tunnel from the k3s/homelab one in shared/zero-trust,
# with its own connector (cloudflared runs on mihal-lxc itself, not on
# cloudflared-lxc). Revoking or destroying this dir cannot touch nocobase-lxc's
# WARP path or the public hostnames, and vice versa.
#
# A route and the account's split-tunnel carve-out are still account-wide, not
# per-tunnel — shared/zero-trust/warp.tf carves out 192.168.1.9/32 for exactly
# that reason. What makes this genuinely isolated from nocobase-lxc's access is
# the device profile below, not the tunnel.
#
# Enrollment is identity-based (the account's built-in Cloudflare login, email
# + password), not a service token: the Windows Cloudflare One Client's service-
# token enrollment never completed its own internal handoff back to Cloudflare
# even with a correctly-configured mdm.xml and a verified-working Access policy
# (confirmed by curl'ing the same endpoint directly with the token headers,
# which got a 302 while the client's own request still 403'd) — a client-side
# issue this repo cannot fix. Identity login is the well-trodden path instead.

data "cloudflare_zone" "this" {
  name = "pavel-usanli.online"
}

locals {
  account_id = data.cloudflare_zone.this.account_id

  # cloudflare_zero_trust_access_application.warp_enrollment in
  # cloudflare/shared/zero-trust. The account allows exactly one Access
  # Application of type "warp" (device enrollment), so this dir attaches its
  # own policy to that existing one by static ID instead of redeclaring it —
  # the same static-reference pattern used for shared Proxmox template IDs.
  warp_enrollment_app_id = "54851aa1-4ec8-4217-9518-252673b4d34d"
}

resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "mihal" {
  account_id = local.account_id
  name       = "mihal-lxc"
  secret     = random_bytes.tunnel_secret.base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "mihal" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.mihal.id

  config {
    warp_routing {
      enabled = true
    }

    # catch-all required by Cloudflare; this tunnel carries no public ingress.
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_zero_trust_tunnel_route" "mihal" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.mihal.id
  network    = "192.168.1.9/32"
  comment    = "mihal-lxc — its own tunnel and route"
}

# The account's built-in "Cloudflare" identity provider (restricted to account
# members) already exists — enrollment logs in with the same email/password
# used for the Cloudflare dashboard, so no separate identity provider is set
# up here.
resource "cloudflare_zero_trust_access_policy" "mihal" {
  account_id     = local.account_id
  application_id = local.warp_enrollment_app_id
  name           = "mihal-lxc identity login"
  precedence     = 2
  decision       = "allow"

  include {
    email = ["kalpakus@gmail.com"]
  }
}

# Non-default device profile, matched to the one account member who enrolls
# for mihal-lxc access.
resource "cloudflare_zero_trust_device_profiles" "mihal" {
  account_id  = local.account_id
  name        = "mihal-lxc"
  description = "Devices enrolled by kalpakus@gmail.com for mihal-lxc access"
  precedence  = 10
  enabled     = true
  match       = "identity.email == \"kalpakus@gmail.com\""
}

# "include" mode, not "exclude": this profile's only entry IS its entire
# routing table. A device matching it gets 192.168.1.9/32 over WARP and
# sends everything else — including nocobase-lxc's 192.168.1.5 — direct to
# the internet, bypassing Cloudflare entirely. That is what makes this
# isolated: the default profile's carve-out in shared/zero-trust/warp.tf is
# never consulted for a device on this profile.
resource "cloudflare_zero_trust_split_tunnel" "mihal" {
  account_id = local.account_id
  policy_id  = cloudflare_zero_trust_device_profiles.mihal.id
  mode       = "include"

  tunnels {
    address     = "192.168.1.9/32"
    description = "mihal-lxc"
  }
}
