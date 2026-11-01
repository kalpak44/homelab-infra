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
    "34.77.99.151",  # 2026-11-01 231 events over 9h across bunker and noco-google-connector: .env, VCS and CMS probes
    "34.55.131.206", # 2026-11-01 107 events in 104s across planner and www: CVE-2025-29927, secret-file and framework probes
  ]

  blocked_ips_expression = format("ip.src in {%s}", join(" ", local.blocked_ips))
}
