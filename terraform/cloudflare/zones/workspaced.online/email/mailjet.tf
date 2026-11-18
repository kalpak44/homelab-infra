# Outbound mail: workspaced-ai sends as any address on the domain through Mailjet's API,
# with the account's existing key pair copied into secret/workspaced-secrets.
import {
  to = cloudflare_record.spf
  id = "f50d5e37234c6b48f3d9522174209184/476461593472334c227cfc7637d96f56"
}

# A changed email replaces the sender, which deletes it in Mailjet and stops outbound mail
# until the domain is verified again. The provider never reads is_default_sender back and
# updates from prior state rather than the plan, so an edit here would not reach Mailjet.
resource "mailjet_sender" "domain" {
  email             = "*@workspaced.online"
  name              = "workspaced"
  email_type        = "transactional"
  is_default_sender = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [is_default_sender]
  }
}

data "mailjet_dns" "this" {
  dns_id = mailjet_sender.domain.dns_id
}

locals {
  mailjet = data.mailjet_dns.this.entries[0]
}

# Mailjet refuses to send as the domain until it finds this token. It checks on its own;
# a mailjet_sender_validate resource is not used because it fails on an active sender.
resource "cloudflare_record" "mailjet_ownership" {
  zone_id = data.cloudflare_zone.this.id
  name    = local.mailjet.ownership_token_record_name
  type    = "TXT"
  content = "\"${local.mailjet.ownership_token}\""
}

# A domain has exactly one SPF record, so every sender — Mailjet and Email Routing's
# forwarding — goes into this one. A second v=spf1 record fails SPF for all of them.
resource "cloudflare_record" "spf" {
  zone_id = data.cloudflare_zone.this.id
  name    = "workspaced.online"
  type    = "TXT"
  content = "\"v=spf1 include:spf.mailjet.com include:_spf.mx.cloudflare.net ~all\""
}

# A TXT string holds at most 255 characters, and Cloudflare stores the key split that way;
# an unsplit value would rewrite the record on every apply.
resource "cloudflare_record" "mailjet_dkim" {
  zone_id = data.cloudflare_zone.this.id
  name    = "mailjet._domainkey"
  type    = "TXT"
  content = "\"${join("\" \"", regexall(".{1,255}", local.mailjet.dkim_record_value))}\""
}
