terraform {
  backend "s3" {
    key                      = "homelab/aws/personal/account.tfstate"
    region                   = "auto"
    profile                  = "homelab-r2"
    shared_config_files      = ["../../config"]
    shared_credentials_files = []

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
