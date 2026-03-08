locals {
  node_ips         = [for node in var.nodes : node.ip]
  cluster_endpoint = "https://${local.node_ips[0]}:6443"
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = var.talos_image_extensions
  }
}

# ephemeral "talos_machine_secrets" "this" {
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# ephemeral "talos_cluster_kubeconfig" "this" {
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.node_ips[0]
}

data "talos_machine_configuration" "this" {
  for_each = { for node in var.nodes : node.ip => node }

  cluster_name     = var.talos_cluster_name
  machine_type     = each.value.type
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = local.node_ips
}

resource "talos_machine_configuration_apply" "this" {
  for_each = { for node in var.nodes : node.ip => node }

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  node                        = each.value.ip
  config_patches = concat(
    [for patch in var.talos_config_patches : yamlencode(patch)],
    [
      yamlencode({
        machine = {
          install = {
            disk = each.value.disk
          }
        }
      })
    ]
  )
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.this
  ]
  node                 = local.node_ips[0]
  client_configuration = talos_machine_secrets.this.client_configuration
}
