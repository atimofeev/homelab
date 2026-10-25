locals {
  node_ips          = [for node in var.nodes : node.ip]
  control_plane_ips = [for node in var.nodes : node.ip if node.type == "controlplane"]
  worker_ips        = [for node in var.nodes : node.ip if node.type == "worker"]
  cluster_endpoint  = "https://${var.talos_api_vip}:6443"
  kubeconfig        = yamldecode(talos_cluster_kubeconfig.this.kubeconfig_raw)
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = var.talos_image_extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode(
    {
      customization = merge(
        {
          systemExtensions = {
            officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
          }
        },
        length(var.talos_image_kernel_args) > 0 ? { extraKernelArgs = var.talos_image_kernel_args } : {}
      )
    }
  )
}

# iPXE netboot-only schematic: wipes EPHEMERAL+STATE on boot
resource "talos_image_factory_schematic" "ipxe" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
        }
        extraKernelArgs = concat(var.talos_image_kernel_args, ["talos.experimental.wipe=system:EPHEMERAL,STATE"])
      }
    }
  )
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
}

resource "talos_machine_secrets" "this" {}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.control_plane_ips[0]

  depends_on = [data.talos_cluster_health.this]
}

resource "local_sensitive_file" "kubeconfig" {
  content = yamlencode(merge(local.kubeconfig, {
    clusters = [for entry in local.kubeconfig.clusters : merge(entry, {
      cluster = merge(entry.cluster, { server = local.cluster_endpoint })
    })]
  }))
  filename        = pathexpand(var.kubeconfig_path)
  file_permission = "0600"
}

data "talos_client_configuration" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  cluster_name         = var.talos_cluster_name
  endpoints            = local.node_ips
  nodes                = local.node_ips
}

resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = pathexpand(var.talosconfig_path)
  file_permission = "0600"
}

data "talos_machine_configuration" "this" {
  for_each = { for node in var.nodes : node.mac => node }

  cluster_endpoint   = local.cluster_endpoint
  cluster_name       = var.talos_cluster_name
  kubernetes_version = var.kubernetes_version
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  machine_type       = each.value.type
  talos_version      = var.talos_version
  config_patches = concat(
    [for patch in var.talos_config_patches : yamlencode(patch)],
    each.value.type == "controlplane" ? [yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = { hardwareAddr = lower(each.value.mac) }
            dhcp           = true
            vip            = { ip = var.talos_api_vip }
          }]
        }
      }
      }), yamlencode({
      apiVersion                 = "v1alpha1"
      kind                       = "KubeFlannelCNIConfig"
      kubeNetworkPoliciesEnabled = true
      }), yamlencode({
      apiVersion    = "v1alpha1"
      kind          = "KubeAPIServerConfig"
      certExtraSANs = distinct(concat([var.talos_api_vip], local.node_ips))
    })] : [],
    [
      yamlencode({
        cluster = {
          inlineManifests = [
            {
              name     = "external-secrets-namespace"
              contents = <<-EOT
              apiVersion: v1
              kind: Namespace
              metadata:
                name: external-secrets
            EOT
            },
            {
              name     = "external-secrets-token"
              contents = <<-EOT
              apiVersion: v1
              kind: Secret
              type: Opaque
              metadata:
                name: external-secrets-token
                namespace: external-secrets
              data:
                token: ${base64encode(var.external_secrets_main_token)}
            EOT
            }
          ]
        }
      }),
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "UnattendedInstallConfig"
        installer = {
          image = data.talos_image_factory_urls.this.urls.installer
        }
        provisioning = {
          diskSelector = {
            match = format("disk.dev_path == %s", jsonencode(each.value.disk))
          }
          wipe = false
        }
      })
    ]
  )
}

# Generate drain credentials without depending on the cluster's post-upgrade health check.
ephemeral "talos_cluster_kubeconfig" "upgrade" {
  machine_secrets = talos_machine_secrets.this.machine_secrets
  cluster_name    = var.talos_cluster_name
  endpoint        = local.cluster_endpoint
}

resource "talos_machine" "this" {
  for_each = { for node in var.nodes : node.mac => node }

  client_configuration            = talos_machine_secrets.this.client_configuration
  machine_configuration           = data.talos_machine_configuration.this[each.key].machine_configuration
  node                            = each.value.ip
  ignore_kubernetes_upgrade_drift = true
  image                           = data.talos_image_factory_urls.this.urls.installer
  kubeconfig_wo                   = ephemeral.talos_cluster_kubeconfig.upgrade.kubeconfig_raw

  on_destroy = {
    reset = false
  }

  depends_on = [routeros_ip_pool.default_dhcp]

  lifecycle {
    prevent_destroy = true
  }
}

resource "talos_cluster" "this" {
  node                 = local.control_plane_ips[0]
  control_plane_nodes  = local.control_plane_ips
  client_configuration = talos_machine_secrets.this.client_configuration
  kubernetes_version   = var.kubernetes_version

  depends_on = [talos_machine.this]

  timeouts = {
    update = "60m"
  }
}

data "talos_cluster_health" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = local.control_plane_ips
  worker_nodes         = local.worker_ips
  endpoints            = local.control_plane_ips

  depends_on = [talos_cluster.this]

  timeouts = {
    read = "10m"
  }
}
