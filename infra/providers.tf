terraform {
  required_version = ">= 1.11.0"

  required_providers {

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.0"
    }

    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.99.1"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }

  }
}
