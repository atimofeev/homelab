resource "kubernetes_manifest" "metallb_ip_address_pool" {
  depends_on = [helm_release.argocd_apps]
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "default"
      namespace = "metallb-system"
    }
    spec = {
      addresses = ["172.18.255.1-172.18.255.25"]
    }
  }
}

resource "kubernetes_manifest" "metallb_l2_advertisement" {
  depends_on = [helm_release.argocd_apps]
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "default"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["default"]
    }
  }
}
