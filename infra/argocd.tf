locals {
  argocd_application = yamldecode(file("${path.module}/../apps/argocd/main.yaml"))
  argocd_root        = yamldecode(file("${path.module}/../apps/argocd-apps/main.yaml"))
  argocd_chart       = local.argocd_application.spec.sources[0]
  argocd_values      = local.argocd_chart.helm.valuesObject

  argocd_policies = flatten([
    for name in ["network-policies.yaml", "kube-system-resource-policies.yaml"] : [
      for document in split("\n---\n", file("${path.module}/../apps/argocd/${name}")) :
      yamldecode(document) if yamldecode(document) != null
    ]
  ])
}

resource "helm_release" "argo_cd" {
  name             = local.argocd_chart.helm.releaseName
  namespace        = local.argocd_application.spec.destination.namespace
  create_namespace = true
  repository       = local.argocd_chart.repoURL
  chart            = local.argocd_chart.chart
  version          = local.argocd_chart.targetRevision
  timeout          = 600

  values = [yamlencode(merge(local.argocd_values, {
    # Gateway API and Dex are installed by GitOps after this seed is running.
    server = merge(local.argocd_values.server, {
      httproute = merge(local.argocd_values.server.httproute, { enabled = false })
    })
    configs = merge(local.argocd_values.configs, {
      cm = merge(local.argocd_values.configs.cm, { "oidc.config" = "" })
    })
    extraObjects = local.argocd_policies
  }))]

  lifecycle {
    ignore_changes  = all
    prevent_destroy = true
  }
}

resource "helm_release" "argocd_apps" {
  depends_on = [helm_release.argo_cd]

  name       = "argocd-apps"
  namespace  = local.argocd_root.metadata.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.10"
  values = [yamlencode({
    applications = {
      (local.argocd_root.metadata.name) = merge(local.argocd_root.spec, {
        namespace = local.argocd_root.metadata.namespace
      })
    }
  })]

  lifecycle {
    ignore_changes  = all
    prevent_destroy = true
  }
}
