variable "domain" {
  type        = string
  description = "Domain name hosted in Cloudflare"
}

variable "kubeconfig_path" {
  type        = string
  default     = "./kubeconfig"
  description = "The path to the kubeconfig file to write."
}

variable "nodes" {
  type = list(object({
    ip   = string
    mac  = string
    disk = string
    type = string
  }))
  description = "A list of baremetal nodes with their IP and MAC addresses."
}

variable "talos_cluster_name" {
  type        = string
  description = "The name of the Talos cluster."
}

variable "talos_config_patches" {
  type        = any
  default     = null
  description = "A list of YAML-encoded configuration patches to apply to the machine configuration."
}

variable "talos_image_extensions" {
  type        = list(string)
  default     = []
  description = "A list of Talos extension names to include in the machine image."
}

variable "talos_version" {
  type        = string
  description = "The version of Talos features to use in generated machine configuration"
}

variable "talosconfig_path" {
  type        = string
  default     = "./talosconfig"
  description = "The path to the kubeconfig file to write."
}
