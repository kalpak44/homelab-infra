provider "aws" {
  region              = "eu-central-1"
  allowed_account_ids = ["039959484327"]
}

provider "github" {
  owner = "kalpak44"
  token = var.github_token
}

variable "github_token" {
  description = "GH_ADMIN_TOKEN used to manage the homelab-infra Actions role variable"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.github_token) > 0
    error_message = "GH_ADMIN_TOKEN is required to configure the Actions role variable."
  }
}
