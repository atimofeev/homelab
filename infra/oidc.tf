locals {
  oidc_hostname   = "oidc.${var.domain}"
  oidc_issuer_url = "https://${local.oidc_hostname}"
  oidc_kube       = talos_cluster_kubeconfig.this.kubernetes_client_configuration

  oidc_documents = {
    "/.well-known/openid-configuration" = merge(jsondecode(data.http.oidc["discovery"].response_body), {
      issuer   = local.oidc_issuer_url
      jwks_uri = "${local.oidc_issuer_url}/openid/v1/jwks"
    })
    "/openid/v1/jwks" = {
      keys = jsondecode(data.http.oidc["jwks"].response_body).keys
    }
  }
}

data "http" "oidc" {
  for_each = {
    discovery = "/.well-known/openid-configuration"
    jwks      = "/openid/v1/jwks"
  }

  url                = "${local.cluster_endpoint}${each.value}"
  ca_cert_pem        = base64decode(local.oidc_kube.ca_certificate)
  client_cert_pem    = base64decode(local.oidc_kube.client_certificate)
  client_key_pem     = base64decode(local.oidc_kube.client_key)
  request_timeout_ms = 10000
  request_headers = {
    Accept = each.key == "jwks" ? "application/jwk-set+json" : "application/json"
  }

  retry {
    attempts     = 3
    min_delay_ms = 1000
    max_delay_ms = 3000
  }

  depends_on = [talos_machine.this, data.talos_cluster_health.this]

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(jsondecode(self.response_body))
      error_message = "The private Kubernetes API must return valid OIDC JSON with HTTP 200."
    }
    postcondition {
      condition = each.key == "jwks" ? try(length(jsondecode(self.response_body).keys) > 0 && alltrue([
        for key in jsondecode(self.response_body).keys : !anytrue([
          for field in ["d", "p", "q", "dp", "dq", "qi", "oth", "k"] : contains(keys(key), field)
        ])
      ]), false) : try(length(jsondecode(self.response_body).id_token_signing_alg_values_supported) > 0, false)
      error_message = "OIDC discovery must list signing algorithms; JWKS must contain public keys only."
    }
  }
}

resource "cloudflare_workers_script" "oidc" {
  account_id         = data.cloudflare_zone.this.account.id
  script_name        = "${var.talos_cluster_name}-oidc"
  main_module        = "oidc-worker.js"
  compatibility_date = "2026-10-24"
  content = templatefile("${path.module}/templates/oidc-worker.js.tftpl", {
    documents = jsonencode(local.oidc_documents)
  })
}

resource "cloudflare_workers_custom_domain" "oidc" {
  account_id = data.cloudflare_zone.this.account.id
  zone_id    = data.cloudflare_zone.this.id
  hostname   = local.oidc_hostname
  service    = cloudflare_workers_script.oidc.script_name
}
