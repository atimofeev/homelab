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

resource "routeros_ip_dhcp_server_lease" "this" {
  for_each = { for node in var.nodes : node.mac => node }

  address     = each.value.ip
  mac_address = each.value.mac
}

locals {
  talos_pxe_url = "https://pxe.factory.talos.dev/pxe/${talos_image_factory_schematic.ipxe.id}/${var.talos_version}/metal-amd64"
}

# iPXE/netboot DHCP options (see homelab issue #6)
resource "routeros_ip_dhcp_server_option" "ipxe_uefi" {
  name  = "ipxe-uefi"
  code  = 67
  value = "'ipxe.efi'"
}

resource "routeros_ip_dhcp_server_option" "talos_script" {
  name  = "talos-script"
  code  = 67
  value = "'${local.talos_pxe_url}'"
}

resource "routeros_ip_dhcp_server_option_sets" "pxe_bios" {
  name    = "pxe-bios"
  options = "ipxe-uefi"
}

resource "routeros_ip_dhcp_server_option_sets" "pxe_uefi" {
  name    = "pxe-uefi"
  options = "ipxe-uefi"
}

resource "routeros_ip_dhcp_server_option_sets" "set_talos" {
  name    = "set-talos"
  options = "talos-script"
}

resource "routeros_ip_dhcp_server_option_matcher" "ipxe_stage2" {
  name          = "0_ipxe_stage2"
  server        = "defconf"
  option_set    = "set-talos"
  code          = 77
  value         = "0x69505845"
  matching_type = "substring"
}

resource "routeros_ip_dhcp_server_option_matcher" "uefi_stage1" {
  name          = "1_uefi_stage1"
  server        = "defconf"
  option_set    = "pxe-uefi"
  code          = 93
  value         = "0x0007"
  matching_type = "exact"
}
