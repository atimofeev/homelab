domain             = "prosto.dev"
kubeconfig_path    = "~/.kube/homelab.yaml"
talosconfig_path   = "~/.talos/config"
talos_cluster_name = "homelab"
talos_api_vip      = "192.168.88.51"
talos_version      = "v1.14.5"
kubernetes_version = "v1.37.1"
talos_config_patches = [
  ({
    machine = {
      kernel = {
        modules = [
          # NOTE: longhorn
          { name = "nbd" },
          { name = "iscsi_tcp" },
          { name = "configfs" },
        ]
      }
    }
  }),
  ({
    apiVersion = "v1alpha1"
    kind       = "KubeNodeConfig"
    labels = {
      "node.kubernetes.io/exclude-from-external-load-balancers" = {
        "$patch" = "delete"
      }
    }
    taints = {
      "node-role.kubernetes.io/control-plane" = {
        "$patch" = "delete"
      }
    }
  })
]
talos_image_extensions  = ["siderolabs/iscsi-tools", "siderolabs/util-linux-tools"] # NOTE: longhorn
talos_image_kernel_args = ["pcie_aspm=off", "e1000e.SmartPowerDownEnable=0"]
nodes = [
  {
    ip   = "192.168.88.252"
    mac  = "10:E7:C6:07:0B:F5"
    disk = "/dev/sda"
    type = "controlplane"
  },
  {
    ip   = "192.168.88.254"
    mac  = "10:E7:C6:11:C0:82"
    disk = "/dev/sda"
    type = "controlplane"
  },
  {
    ip   = "192.168.88.253"
    mac  = "F4:39:09:2B:B5:24"
    disk = "/dev/sda"
    type = "controlplane"
  },
]
