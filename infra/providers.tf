terraform {
  required_version = ">= 1.11.0"

  required_providers {

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
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

    http = {
      source  = "hashicorp/http"
      version = "3.6.3"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }

  }
}

# Use the cluster created by this stack, not an existing local kubeconfig.
provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  }
}
