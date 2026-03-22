locals {
  argocd-namespace = "argocd"
}

resource "kubernetes_namespace" "argo_cd" {
  metadata {
    name = local.argocd-namespace
  }
}

resource "helm_release" "argo_cd" {
  depends_on = [kubernetes_namespace.argo_cd]

  chart      = "argo-cd"
  name       = "argo-cd"
  namespace  = local.argocd-namespace
  repository = "https://argoproj.github.io/argo-helm"
  version    = "9.4.6"

  values = [
    yamlencode({
      crds = {
        keepj = false
      }
      global = {
        domain = "argocd.prosto.dev"
      }
      server = {
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          annotations = {
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
          }
        }
      }
    })
  ]

}

resource "helm_release" "argocd_apps" {
  depends_on = [kubernetes_namespace.argo_cd, helm_release.argo_cd]

  chart      = "argocd-apps"
  name       = "argocd-apps"
  namespace  = local.argocd-namespace
  repository = "https://argoproj.github.io/argo-helm"
  version    = "2.0.4"

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
