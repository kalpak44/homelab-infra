# Adopted from the dashboard. A value that does not start with `v=DMARC1` is ignored by
# every receiver, which leaves the domain with no policy and no aggregate reports.
import {
  to = cloudflare_record.dmarc
  id = "e6d8e2575b878bbc1e52039d45c87e0e/2d98a7ba2f1b0979712a67f76fcbc901"
}

# Tighten to p=quarantine once the reports show Mailjet and Email Routing both pass.
resource "cloudflare_record" "dmarc" {
  zone_id = data.cloudflare_zone.this.id
  name    = "_dmarc"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:contact@pavel-usanli.online\""
}
