terraform {
  backend "s3" {
    # bucket, access_key, secret_key, and endpoint passed via -backend-config
    # See README for local init instructions and CI secrets
    key    = "dev/terraform.tfstate"
    region = "auto"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}