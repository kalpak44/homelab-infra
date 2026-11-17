# The edge half of the blocklist .github/workflows/ai-security-agent.yml maintains. Only
# the worst offenders reach here — CrowdSec carries every ban and covers *.internal too,
# while this stops the traffic before it crosses the tunnel.
#
# One list, zones/blocked-ips.txt, read by every zone's edge/ dir. Each zone allows a
# single http_request_firewall_custom entrypoint, so the rule is added inside that zone's
# existing ruleset, never in a ruleset of its own.
locals {
  # Kept in zones/blocked-ips.txt rather than here, so a night's bans grow a plain list
  # instead of this file. Comment and blank lines are dropped; the file is the only edit
  # point.
  blocked_ips = [
    for line in split("\n", file("${path.module}/../../blocked-ips.txt")) :
    trimspace(line)
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]

  blocked_ips_expression = format("ip.src in {%s}", join(" ", local.blocked_ips))
}
