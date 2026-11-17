# Outbound mail: Gmail "Send mail as" relays contact@ through Mailjet SMTP. The senders
# and their DNS records were set up by hand and are adopted here.
import {
  to = mailjet_sender.domain
  id = 6485092037
}

import {
  to = mailjet_sender.contact
  id = 6485098959
}

import {
  to = cloudflare_record.spf
  id = "e6d8e2575b878bbc1e52039d45c87e0e/241fdcedcddbd95e2ed8585758e533d7"
}

import {
  to = cloudflare_record.mailjet_dkim
  id = "e6d8e2575b878bbc1e52039d45c87e0e/2b61c7cc6bde2761ba3f72e8990a8684"
}

# A changed email replaces the sender, which deletes it in Mailjet and stops outbound mail
# until the domain is verified again. The provider never reads is_default_sender back and
# updates from prior state rather than the plan, so an edit here would not reach Mailjet.
resource "mailjet_sender" "domain" {
  email             = "*@pavel-usanli.online"
  name              = "personal"
  email_type        = "unknown"
  is_default_sender = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [is_default_sender]
  }
}

resource "mailjet_sender" "contact" {
  email             = "contact@pavel-usanli.online"
  name              = "personal"
  email_type        = "unknown"
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
  mailjet_dkim = data.mailjet_dns.this.entries[0].dkim_record_value
}

# A domain has exactly one SPF record, so every sender — Mailjet and Email Routing's
# forwarding — goes into this one. A second v=spf1 record fails SPF for all of them.
resource "cloudflare_record" "spf" {
  zone_id = data.cloudflare_zone.this.id
  name    = "pavel-usanli.online"
  type    = "TXT"
  content = "\"v=spf1 include:spf.mailjet.com include:_spf.mx.cloudflare.net ~all\""
}

# A TXT string holds at most 255 characters, and Cloudflare stores the key split that way;
# an unsplit value would rewrite the record on every apply.
resource "cloudflare_record" "mailjet_dkim" {
  zone_id = data.cloudflare_zone.this.id
  name    = "mailjet._domainkey"
  type    = "TXT"
  content = "\"${join("\" \"", regexall(".{1,255}", local.mailjet_dkim))}\""
}
