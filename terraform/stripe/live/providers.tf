# Reads STRIPE_API_KEY from the environment: the live account's `terraform`
# restricted key. One account serves every app (workspaced-ai, proklinator,
# pavel-usanli.online).
provider "stripe" {}
