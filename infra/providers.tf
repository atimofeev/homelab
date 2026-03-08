terraform {
  required_version = ">= 1.11.0"

  required_providers {

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">=5.18.0"
    }

    routeros = {
      source  = "terraform-routeros/routeros"
      version = ">=1.99.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = ">=0.11.0-beta.1"
    }

  }
}
