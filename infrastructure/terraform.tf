terraform {
  required_version = ">= 1.7.0"

  required_providers {

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.36.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }

  }
}

provider "kubernetes" {
  config_path = "~/.kube/homelab.yml"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/homelab.yml"
  }
}
