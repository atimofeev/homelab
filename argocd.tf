locals {
  argocd-namespace = "argocd"
}

resource "kubernetes_namespace_v1" "argo_cd" {
  metadata {
    name = local.argocd-namespace
  }
}

resource "helm_release" "argo_cd" {
  depends_on = [kubernetes_namespace_v1.argo_cd]

  chart      = "argo-cd"
  name       = "argo-cd"
  namespace  = local.argocd-namespace
  repository = "https://argoproj.github.io/argo-helm"
  version    = "10.11.6"

  values = [
    yamlencode({
      crds = {
        keepj = false
      }
      global = {
        domain = "argocd.prosto.dev"
        # The chart's server policy is allow-all; replace it via extraObjects.
        networkPolicy = {
          create = false
        }
      }
      controller = {
        networkPolicy = { create = true }
      }
      repoServer = {
        networkPolicy = { create = true }
      }
      redis = {
        networkPolicy = { create = true }
      }
      notifications = {
        networkPolicy = { create = true }
      }
      extraObjects = yamldecode(file("${path.module}/argocd-network-policies.yaml"))
      dex = {
        enabled = false
      }
      configs = {
        params = {
          "server.insecure" = true
        }
        cm = {
          url                       = "https://argocd.prosto.dev"
          "admin.enabled"           = "false"
          "users.anonymous.enabled" = "false"
          "oidc.config" = yamlencode({
            name            = "Google"
            issuer          = "https://dex.prosto.dev"
            clientID        = "argocd"
            clientSecret    = "$argocd-dex:client-secret"
            requestedScopes = ["openid", "profile", "email", "offline_access"]
          })
        }
        rbac = {
          "policy.default" = ""
          "policy.csv"     = "g, legalaze94@gmail.com, role:admin"
          scopes           = "[email]"
        }
      }
      server = {
        ingress = {
          enabled = false
        }
        httproute = {
          enabled = true
          annotations = {
            "item.homer.rajsingh.info/name"     = "ArgoCD"
            "item.homer.rajsingh.info/subtitle" = "GitOps Continuous Delivery"
            "item.homer.rajsingh.info/logo"     = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/webp/argo-cd.webp"
            "service.homer.rajsingh.info/name"  = "System"
            "service.homer.rajsingh.info/icon"  = "fas fa-cogs"
          }
          parentRefs = [{
            group       = "gateway.networking.k8s.io"
            kind        = "Gateway"
            name        = "traefik-gateway"
            namespace   = "traefik"
            sectionName = "websecure"
          }]
          hostnames = ["argocd.prosto.dev"]
        }
      }
    })
  ]

}

resource "helm_release" "argocd_apps" {
  depends_on = [kubernetes_namespace_v1.argo_cd, helm_release.argo_cd]

  chart      = "argocd-apps"
  name       = "argocd-apps"
  namespace  = local.argocd-namespace
  repository = "https://argoproj.github.io/argo-helm"
  version    = "2.0.7"

  values = [
    yamlencode({
      applications = {
        argocd-apps = {
          namespace = local.argocd-namespace
          project   = "default"
          source = {
            repoURL        = "https://github.com/atimofeev/homelab"
            targetRevision = "HEAD"
            path           = "apps"
            directory = {
              recurse = true
              include = "*/main.yaml"
            }
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = local.argocd-namespace
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
          }
          syncOptions = [
            "CreateNamespace=true"
          ]
        }
      }
    })
  ]
}
