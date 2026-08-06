terraform {
  backend "s3" {
    endpoint = "https://83bd3e9d3616aec28ad6e6c04a44eac3.r2.cloudflarestorage.com"
    bucket   = "tfstate-homelab"

    key    = "infra/terraform.tfstate"
    region = "auto"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }
}
