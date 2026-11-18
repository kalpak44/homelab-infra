provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
# Reads MJ_APIKEY_PUBLIC and MJ_APIKEY_PRIVATE from the environment.
provider "mailjet" {}
