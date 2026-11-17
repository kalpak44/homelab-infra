terraform {
  required_version = ">= 1.7"

  required_providers {
    stripe = {
      source = "stripe/stripe"
      # Pinned exactly: a 0.x provider may change resource shapes between minors.
      version = "0.3.1"
    }
  }
}
