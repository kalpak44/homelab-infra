# The edge half of the blocklist .github/workflows/ai-security-agent.yml maintains. Only
# the worst offenders reach here — CrowdSec carries every ban and covers *.internal too,
# while this stops the traffic before it crosses the tunnel.
#
# One list, read by both zones' rulesets. Each zone allows a single
# http_request_firewall_custom entrypoint, so the rule is added inside the ruleset that
# already exists in edge-ports.tf and waf-proklinator.tf, never in a ruleset of its own.
locals {
  # Newest last. The comment is the evidence: without the date and the behaviour, nothing
  # here can ever be judged stale and the list only grows.
  blocked_ips = [
    # "203.0.113.4", # 2026-11-01 wp-admin and /.env sweep across both zones
  ]

  blocked_ips_expression = format("ip.src in {%s}", join(" ", local.blocked_ips))
}
