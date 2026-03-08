variable "domain" {
  type        = string
  description = "Domain name hosted in Cloudflare"
}

variable "nodes" {
  type = list(object({
    ip  = string
    mac = string
  }))
  description = "A list of baremetal nodes with their IP and MAC addresses."
}

variable "talos_image_extensions" {
  type        = list(string)
  description = "A list of Talos extension names to include in the machine image."
}

variable "talos_version" {
  type        = string
  description = "The version of talos features to use in generated machine configuration"
}
