# Reads AUTH0_CLIENT_ID and AUTH0_CLIENT_SECRET from the environment. The tenant is named
# here rather than read from AUTH0_DOMAIN, so another tenant's credentials fail to sign in
# instead of applying this config to it.
provider "auth0" {
  domain = "workspaced.eu.auth0.com"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
