locals {
  # Scoped to our two hostnames rather than left zone-wide. The zone also answers for
  # app.proklinator.online, which stands in for a customer domain we do not control;
  # it is DNS-only today, but orange-clouding it would hand it these rules.
  proklinator_waf_hosts = join(" ", [for h in values(local.proklinator_apps) : "\"${h}\""])

  # The site is a static build plus three /api routes, so none of these can resolve.
  # Matched with `contains`, not a pattern: the `matches` operator needs a Business
  # plan, and this zone is on Free.
  proklinator_scanner_paths = [
    ".php",
    ".asp",
    ".jsp",
    ".cgi",
    "/wp-",
    "/xmlrpc",
    "/.git",
    "/.env",
    "/.aws",
    "/.ssh",
    "/.svn",
    "/phpmyadmin",
    "/administrator",
    "/adminer",
    "/cgi-bin/",
    "/vendor/",
  ]

  # Tools that announce themselves. Deliberately no curl, wget or python-requests:
  # those are what a health check, an uptime probe and a deploy script all send.
  proklinator_scanner_agents = [
    "sqlmap",
    "nikto",
    "nmap",
    "masscan",
    "zgrab",
    "nuclei",
    "wpscan",
    "dirbuster",
    "gobuster",
    "feroxbuster",
    "acunetix",
    "netsparker",
  ]
}

# The proklinator zone's one WAF custom ruleset. Cloudflare allows a single entrypoint
# per phase and writing it REPLACES the whole rule list, so every custom rule for this
# zone belongs here — one added in the dashboard is deleted by the next apply.
#
# Never add a `skip` carrying `ruleset = "current"` above a rule meant to run; it ends
# evaluation of this ruleset for every request it matches.
resource "cloudflare_ruleset" "proklinator_scanners" {
  zone_id = data.cloudflare_zone.proklinator.id
  # Cloudflare names a phase entrypoint "default" and rewrites anything else.
  name  = "default"
  kind  = "zone"
  phase = "http_request_firewall_custom"

  # The Free plan caps this zone at five custom rules, so each one covers a family
  # rather than a single path. Exploit payloads for named CVEs are already handled by
  # the Cloudflare Managed Free Ruleset; what it does not cover is plain enumeration.
  rules {
    ref         = "block_scanner_paths"
    action      = "block"
    description = "Block paths the site and its API never serve"
    enabled     = true

    expression = format("(http.host in {%s}) and (%s)",
      local.proklinator_waf_hosts,
      join(" or ", [for p in local.proklinator_scanner_paths : "lower(http.request.uri.path) contains \"${p}\""])
    )
  }

  rules {
    ref         = "block_scanner_agents"
    action      = "block"
    description = "Block self-identifying scanning tools"
    enabled     = true

    expression = format("(http.host in {%s}) and (%s)",
      local.proklinator_waf_hosts,
      join(" or ", [for a in local.proklinator_scanner_agents : "lower(http.user_agent) contains \"${a}\""])
    )
  }

  # The static build answers GET and HEAD; the API adds POST on one route. OPTIONS is
  # left alone even though the site is same-origin today, because blocking it breaks
  # CORS preflight the moment anything calls the API from another origin.
  rules {
    ref         = "block_unused_methods"
    action      = "block"
    description = "Block HTTP methods neither the site nor the API implements"
    enabled     = true

    expression = format(
      "(http.host in {%s}) and (http.request.method in {\"PUT\" \"DELETE\" \"PATCH\" \"TRACE\" \"CONNECT\"})",
      local.proklinator_waf_hosts
    )
  }
}

# Rate limiting is its own phase entrypoint, so it cannot live in the ruleset above.
# This is the zone's only rate limiting rule — Free allows exactly one — and it is
# spent on the one route that reaches Stripe with a live key.
resource "cloudflare_ruleset" "proklinator_ratelimit" {
  zone_id = data.cloudflare_zone.proklinator.id
  # Cloudflare names a phase entrypoint "default" and rewrites anything else.
  name  = "default"
  kind  = "zone"
  phase = "http_ratelimit"

  rules {
    ref         = "ratelimit_checkout_session"
    action      = "block"
    description = "Throttle Stripe Checkout Session creation per client IP"
    enabled     = true

    # Matched on path alone. Free restricts which fields a rate limiting expression may
    # read, and host and method are not among them — no loss here, because this path
    # exists on no other hostname in the zone and a GET to it only ever 404s.
    expression = "starts_with(http.request.uri.path, \"/api/checkout\")"

    ratelimit {
      # cf.colo.id is mandatory on every rate limiting rule and must not appear in the
      # expression; Cloudflare counts per data centre on its own.
      characteristics = ["cf.colo.id", "ip.src"]

      # Free permits one period and one timeout, both 10s. Five checkout attempts in
      # ten seconds is no longer a buyer, and the ten-second block is enough to stop a
      # burst opening Stripe sessions faster than crowdsec's bucket can overflow.
      period              = 10
      requests_per_period = 5
      mitigation_timeout  = 10
    }
  }
}
