data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = var.talos_image_extensions
  }
}

ephemeral "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

ephemeral "talos_cluster_kubeconfig" "this" {
  client_configuration = {
    ca_certificate     = talos_machine_secrets.this.ca_certificate
    client_certificate = talos_machine_secrets.this.client_certificate
    client_key         = talos_machine_secrets.this.client_key
  }
  node = var.nodes[0].ip
}
