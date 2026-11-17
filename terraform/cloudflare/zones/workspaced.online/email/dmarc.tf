# Without a policy, anyone can send as sales@, support@ or investor@ and receivers have no
# rule to reject it by. Email Routing writes SPF itself, so only DMARC is declared here.
# Tighten to p=quarantine once the aggregate reports show nothing legitimate failing.
resource "cloudflare_record" "dmarc" {
  zone_id = data.cloudflare_zone.this.id
  name    = "_dmarc"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:support@workspaced.online\""
}
