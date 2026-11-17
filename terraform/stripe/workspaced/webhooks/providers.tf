locals {
  account_id = "acct_1IAIb3ABYXXbGldT"
}

provider "stripe" {
  api_key = var.stripe_api_key_workspaced
}

# Each app has its own Stripe account, so a key pasted into the wrong secret would apply
# this config to another app's account; refuse to plan unless the key is this account's.
data "http" "account" {
  url = "https://api.stripe.com/v1/account"

  request_headers = {
    Authorization = "Bearer ${var.stripe_api_key_workspaced}"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && try(jsondecode(self.response_body).id, "") == local.account_id
      error_message = "TF_VAR_stripe_api_key_workspaced is not a key for ${local.account_id}."
    }
  }
}
