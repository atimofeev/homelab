domain             = "prosto.dev"
talos_cluster_name = "homelab"
talos_config_patches = [
  ({
    machine = {
      kernel = {
        modules = [
          # NOTE: longhorn
          { name = "nbd" },
          { name = "iscsi_tcp" },
          { name = "iscsi_generic" },
          { name = "configfs" },
        ]
      }
    }
  }),
  ({
    machine = {
      allowSchedulingOnControlPlanes = true
    }
  })
]
talos_version          = "v1.12.4"
talos_image_extensions = ["iscsi-tools", "util-linux-tools"] # NOTE: longhorn
nodes = [
  {
    ip   = "192.168.88.254"
    mac  = "F4:39:09:2B:B5:24"
    disk = "/dev/sda"
    type = "controlplane"
  },
  {
    ip   = "192.168.88.250"
    mac  = "10:E7:C6:11:C0:82"
    disk = "/dev/sda"
    type = "controlplane"
  },
  {
    ip   = "192.168.88.249"
    mac  = "10:E7:C6:07:0B:F5"
    disk = "/dev/sda"
    type = "controlplane"
  }
]
