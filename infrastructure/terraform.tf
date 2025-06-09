terraform {
  required_version = "> 1.7.0, <= 1.9.1"

  required_providers {

    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.8.0"
    }

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
  config_path = kind_cluster.default.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = kind_cluster.default.kubeconfig_path
  }
}
