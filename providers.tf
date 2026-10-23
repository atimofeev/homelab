terraform {
  required_version = ">= 1.7.0"

  required_providers {

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.4.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }

  }
}

provider "kubernetes" {
  config_path = "~/.kube/homelab.yaml"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/homelab.yaml"
  }
}
