locals {
  blocky_lb_address = "192.168.88.50"
}

resource "routeros_ip_dns" "this" {
  allow_remote_requests = true
  servers               = [local.blocky_lb_address]
}

resource "routeros_tool_netwatch" "blocky_monitor" {
  name              = "blocky_monitor"
  comment           = "Monitor Blocky k8s DNS Service"
  host              = local.blocky_lb_address
  type              = "tcp-conn"
  port              = 53
  interval          = "10s"
  thr_tcp_conn_time = "150ms"

  down_script = <<EOF
/ip dns set servers=1.1.1.1,1.0.0.1
/ip dns cache flush
:log error "Blocky TCP:53 unreachable. Switched to Fallback (1.1.1.1)."
EOF

  up_script = <<EOF
/ip dns set servers=${local.blocky_lb_address}
/ip dns cache flush
:log info "Blocky TCP:53 restored. Routing queries to k8s."
EOF
}

resource "routeros_ip_cloud" "this" {
  ddns_enabled         = "yes"
  ddns_update_interval = "15m"
}
