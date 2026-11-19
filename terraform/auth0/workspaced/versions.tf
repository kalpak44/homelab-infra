terraform {
  required_version = ">= 1.7"

  required_providers {
    auth0 = {
      source  = "auth0/auth0"
      version = "~> 1.62"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}
