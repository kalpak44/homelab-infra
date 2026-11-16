# workspaced-ai's Domain Connect signing key; a DNS provider refuses any apply request it
# cannot verify against these records. The private half is domain-connect-private-key in
# secret/workspaced-secrets.
locals {
  domain_connect_key = trimspace(file("${path.module}/domain-connect-dck1.pub"))

  # One TXT string holds 255 characters, so the key is split into numbered parts.
  domain_connect_key_parts = [
    for i in range(ceil(length(local.domain_connect_key) / 200)) :
    substr(local.domain_connect_key, i * 200, 200)
  ]
}

resource "cloudflare_record" "domain_connect_key" {
  count = length(local.domain_connect_key_parts)

  zone_id = data.cloudflare_zone.workspaced.id
  name    = "_dck1"
  type    = "TXT"
  content = "p=${count.index + 1},a=RS256,d=${local.domain_connect_key_parts[count.index]}"
  ttl     = 3600
}
