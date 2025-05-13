locals {
  argocd-namespace = "argocd"
}

resource "kubernetes_namespace" "argo_cd" {
  depends_on = [kind_cluster.default]

  metadata {
    name = local.argocd-namespace
  }
}

# TODO: change appearance theme to auto
# TODO: add `system` project
resource "helm_release" "argo_cd" {
  depends_on = [kubernetes_namespace.argo_cd]

  chart           = "argo-cd"
  name            = "argo-cd"
  namespace       = local.argocd-namespace
  repository      = "https://argoproj.github.io/argo-helm"
  upgrade_install = true
  version         = "8.0.0"

  set {
    name  = "crds.keep"
    value = false
  }

  set {
    name  = "global.domain"
    value = "argocd.k8s.homelab"
  }

  set_list {
    name  = "server.extraArgs"
    value = ["--insecure"]
  }

  set {
    name  = "server.ingress.enabled"
    value = true
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "nginx"
  }

}

resource "helm_release" "argocd_apps" {
  depends_on = [kubernetes_namespace.argo_cd, helm_release.argo_cd]

  chart           = "argocd-apps"
  name            = "argocd-apps"
  namespace       = local.argocd-namespace
  repository      = "https://argoproj.github.io/argo-helm"
  upgrade_install = true
  version         = "2.0.2"

  values = [
    file("./argocd-system.yaml"),
    file("./argocd-apps.yaml")
  ]
}
