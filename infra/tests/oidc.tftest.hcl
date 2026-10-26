mock_provider "cloudflare" {
  mock_data "cloudflare_zone" {
    defaults = {
      id      = "00000000000000000000000000000001"
      account = { id = "00000000000000000000000000000002", name = "fixture" }
    }
  }
}

mock_provider "routeros" {}
mock_provider "local" {}
mock_provider "http" {}

mock_provider "talos" {
  mock_resource "talos_cluster_kubeconfig" {
    defaults = {
      kubeconfig_raw = "{\"clusters\":[]}"
      kubernetes_client_configuration = {
        host               = "https://192.0.2.10:6443"
        ca_certificate     = "Zml4dHVyZS1jYQ=="
        client_certificate = "Zml4dHVyZS1jZXJ0"
        client_key         = "Zml4dHVyZS1rZXk="
      }
    }
  }
}

variables {
  domain                  = "example.com"
  talos_cluster_name      = "fixture"
  talos_api_vip           = "192.0.2.10"
  talos_version           = "v1.14.4"
  kubernetes_version      = "v1.37.1"
  talos_config_patches    = []
  kubeconfig_path         = "/unused/kubeconfig"
  talosconfig_path        = "/unused/talosconfig"
  talos_image_extensions  = []
  talos_image_kernel_args = []
  nodes = [
    { ip = "192.0.2.11", mac = "02:00:00:00:00:11", disk = "/dev/sda", type = "controlplane" },
    { ip = "192.0.2.12", mac = "02:00:00:00:00:12", disk = "/dev/sda", type = "worker" },
  ]
}

run "public_issuer_and_private_metadata_reads" {
  command = plan

  assert {
    condition     = yamldecode(data.talos_machine_configuration.this["02:00:00:00:00:11"].config_patches[3]).issuer.issuerURL == "https://oidc.example.com"
    error_message = "One apply must converge directly to the public issuer."
  }

  assert {
    condition     = !can(yamldecode(data.talos_machine_configuration.this["02:00:00:00:00:11"].config_patches[3]).issuer.privateKey)
    error_message = "OIDC patches must not replace the generated signing key."
  }

  assert {
    condition     = yamldecode(data.talos_machine_configuration.this["02:00:00:00:00:11"].config_patches[3]).accepted.issuers == ["https://192.0.2.10:6443"]
    error_message = "Only the legacy issuer belongs in accepted.issuers; Talos adds the issuing URL automatically and duplicates crash kube-apiserver."
  }

  assert {
    condition     = toset(yamldecode(data.talos_machine_configuration.this["02:00:00:00:00:11"].config_patches[3]).accepted.audiences) == toset(["https://192.0.2.10:6443", "https://oidc.example.com"])
    error_message = "Both old and new API audiences must remain accepted."
  }

  assert {
    condition     = length(data.talos_machine_configuration.this["02:00:00:00:00:12"].config_patches) == 2
    error_message = "Workers must not receive service-account issuer patches."
  }

  assert {
    condition     = cloudflare_workers_custom_domain.oidc.hostname == "oidc.example.com" && cloudflare_workers_custom_domain.oidc.service == cloudflare_workers_script.oidc.script_name
    error_message = "The public hostname must point directly at the static Worker."
  }

  assert {
    condition     = data.http.oidc["jwks"].url == "https://192.0.2.10:6443/openid/v1/jwks" && data.http.oidc["jwks"].ca_cert_pem == "fixture-ca" && data.http.oidc["jwks"].client_cert_pem == "fixture-cert" && data.http.oidc["jwks"].client_key_pem == "fixture-key"
    error_message = "Metadata must be read privately with verified mTLS."
  }

  assert {
    condition     = data.http.oidc["jwks"].request_headers.Accept == "application/jwk-set+json" && data.http.oidc["discovery"].request_headers.Accept == "application/json"
    error_message = "JWKS requires application/jwk-set+json; discovery requires application/json."
  }
}
