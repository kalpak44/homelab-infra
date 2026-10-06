# ─── WARP path to nocobase-lxc ────────────────────────────────────────────────
#
# Lets a WARP-enrolled client reach 192.168.1.5 with no public hostname, no
# ingress rule and no open WAN port. Built for the deepcraft-nocobase CI runner.
#
# This is a *private network route*, not an ingress rule, so it does not touch
# cloudflare_zero_trust_tunnel_cloudflared_config and cannot disturb the public
# hostnames or the http_status:404 catch-all.
#
# mihal-lxc's own route, tunnel and service token live in
# cloudflare/shared/mihal-lxc-warp/ instead of here — only the split-tunnel
# carve-out below is unavoidably shared, because the default device profile
# (cloudflare_zero_trust_split_tunnel.default) is one account-wide setting no
# matter which tunnel advertises a route into it.

locals {
  warp_account_id = data.cloudflare_zone.this.account_id

  # Only this host is routed. Deliberately a /32 and not 192.168.1.0/24: an
  # enrolled runner must not be able to reach Postgres, the Proxmox UI or
  # anything else on the LAN.
  warp_target_cidr = "192.168.1.5/32"

  # The mihal-lxc target, routed by its own dedicated tunnel in
  # cloudflare/shared/mihal-lxc-warp/ — carved out here anyway, since this
  # split-tunnel profile is the one place that is genuinely a single
  # account-wide resource.
  warp_target_cidr_mihal = "192.168.1.9/32"

  # 192.168.0.0/16 minus 192.168.1.5/32 and 192.168.1.9/32. Verified to cover
  # 65534 of the 65536 addresses, with every other 192.168.1.0/24 address still
  # excluded. Recompute if either warp_target_cidr* changes:
  #   python3 -c "
  #   import ipaddress as i
  #   nets = [i.ip_network('192.168.0.0/16')]
  #   for ex in [i.ip_network('192.168.1.5/32'), i.ip_network('192.168.1.9/32')]:
  #       nets = [r for n in nets for r in n.address_exclude(ex)]
  #   print(sorted(nets, key=lambda n: (n.network_address, n.prefixlen)))"
  warp_lan_carveout = [
    "192.168.0.0/24", "192.168.1.0/30", "192.168.1.4/32", "192.168.1.6/31",
    "192.168.1.8/32", "192.168.1.10/31", "192.168.1.12/30", "192.168.1.16/28",
    "192.168.1.32/27", "192.168.1.64/26", "192.168.1.128/25", "192.168.2.0/23",
    "192.168.4.0/22", "192.168.8.0/21", "192.168.16.0/20", "192.168.32.0/19",
    "192.168.64.0/18", "192.168.128.0/17",
  ]

  # Cloudflare's stock exclude list, reproduced verbatim except that
  # 192.168.0.0/16 is replaced by the carve-out above.
  #
  # cloudflare_split_tunnel REPLACES the entire list on every apply — exactly
  # like the tunnel ingress config. Anything dropped from here is silently
  # un-excluded for every WARP device in the account, which would route that
  # traffic into the tunnel and black-hole it. Never prune this list to "just
  # the interesting entries".
  warp_split_tunnel_exclude = concat(
    [
      { address = "ff05::/16", description = null },
      { address = "ff04::/16", description = null },
      { address = "ff03::/16", description = null },
      { address = "ff02::/16", description = null },
      { address = "ff01::/16", description = null },
      { address = "fe80::/10", description = "IPv6 Link Local" },
      { address = "fd00::/8", description = null },
      { address = "255.255.255.255/32", description = "DHCP Broadcast" },
      { address = "240.0.0.0/4", description = null },
      { address = "224.0.0.0/24", description = null },
      { address = "192.0.0.0/24", description = null },
      { address = "172.16.0.0/12", description = null },
      { address = "169.254.0.0/16", description = "DHCP Unspecified" },
      { address = "100.64.0.0/10", description = null },
      { address = "10.0.0.0/8", description = null },
    ],
    [for c in local.warp_lan_carveout : {
      address     = c
      description = "LAN except ${local.warp_target_cidr}, ${local.warp_target_cidr_mihal}"
    }]
  )
}

resource "cloudflare_zero_trust_tunnel_route" "nocobase" {
  account_id = local.warp_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
  network    = local.warp_target_cidr
  comment    = "nocobase-lxc — WARP-only access for deepcraft-nocobase CI"
}

# Credentials the CI runner enrols WARP with. client_secret is only readable
# from state, so recover it with:
#   just output cloudflare shared/zero-trust warp_service_token_client_secret
resource "cloudflare_zero_trust_access_service_token" "nocobase_ci" {
  account_id = local.warp_account_id
  name       = "deepcraft-nocobase-ci"
  duration   = "8760h"
}

# Device enrolment is an Access application of type "warp". Without a policy
# whose decision is non_identity, a service token cannot enrol and the client
# fails with "Registration Missing".
#
# Cloudflare owns the name and launcher visibility of a warp-type app and rewrites
# both server-side; these values match what it actually sets, so the plan stays
# clean. Renaming this in the config only produces a diff that never converges.
resource "cloudflare_zero_trust_access_application" "warp_enrollment" {
  account_id           = local.warp_account_id
  name                 = "Warp Login App"
  type                 = "warp"
  session_duration     = "24h"
  app_launcher_visible = false
}

resource "cloudflare_zero_trust_access_policy" "warp_ci" {
  account_id     = local.warp_account_id
  application_id = cloudflare_zero_trust_access_application.warp_enrollment.id
  name           = "deepcraft-nocobase CI service token"
  precedence     = 1
  decision       = "non_identity"

  include {
    service_token = [cloudflare_zero_trust_access_service_token.nocobase_ci.id]
  }
}

# Applies to the default device profile (policy_id omitted). WARP excludes all
# of RFC1918 by default, which is why a route alone is not enough to reach the
# box — the carve-out above is what actually lets 192.168.1.5 through.
resource "cloudflare_zero_trust_split_tunnel" "default" {
  account_id = local.warp_account_id
  mode       = "exclude"

  dynamic "tunnels" {
    for_each = local.warp_split_tunnel_exclude
    content {
      address     = tunnels.value.address
      description = tunnels.value.description
    }
  }
}
