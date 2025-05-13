resource "kind_cluster" "default" {
  name            = "homelab-docker"
  wait_for_ready  = true
  kubeconfig_path = pathexpand("~/.kube/homelab-docker.yml")
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      kubeadm_config_patches = compact([<<EOF
kind: ClusterConfiguration
controllerManager:
  extraArgs:
    bind-address: 0.0.0.0
etcd:
  local:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
scheduler:
  extraArgs:
    bind-address: 0.0.0.0
EOF
        ,
        <<EOF
kind: KubeProxyConfiguration
metricsBindAddress: 0.0.0.0
EOF
      ])

      extra_port_mappings {
        container_port = 53
        host_port      = 5333
        protocol       = "UDP"
      }

      extra_port_mappings {
        container_port = 53
        host_port      = 5333
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }

      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }

    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}
