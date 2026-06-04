output "alias_address" {
  description = "The email alias that was created"
  value       = "${var.alias_name}@${var.domain}"
}

output "rule_tag" {
  description = "Cloudflare tag of the routing rule"
  value       = cloudflare_email_routing_rule.alias.tag
}