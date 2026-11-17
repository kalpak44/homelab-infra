terraform {
  required_version = ">= 1.7"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    mailjet = {
      source  = "enalean/mailjet"
      version = "~> 0.2"
    }
  }
}