# Custom hostnames (tunnels/homelab/saas.tf) inherit these, which cuts both ways.
# Destroying this resource reverts every zone setting to its pre-apply value, not just the
# ones named here.
resource "cloudflare_zone_settings_override" "this" {
  zone_id = data.cloudflare_zone.this.id

  settings {
    # The referer check compares against pavel-usanli.online even on an inherited
    # custom hostname, so a customer's own images read as hotlinking (1011).
    hotlink_protection = "off"

    # Off, the edge served the admin UI over cleartext HTTP. nginx cannot fix that
    # — it only sees the tunnel's decrypted leg, so by the time X-Forwarded-Proto
    # says http:// the credentials are already sent. Covers the alternate HTTP
    # ports too; their HTTPS twins are edge-ports.tf's job.
    always_use_https = "on"
  }
}
