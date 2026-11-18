# Without a policy, anyone can send as contact@, sales@ or support@ and receivers have no
# rule to reject it by. SPF and DKIM are in mailjet.tf.
# Tighten to p=quarantine once the reports show Mailjet and Email Routing both pass.
resource "cloudflare_record" "dmarc" {
  zone_id = data.cloudflare_zone.this.id
  name    = "_dmarc"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:support@workspaced.online\""
}
