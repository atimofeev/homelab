resource "routeros_ip_cloud" "this" {
  ddns_enabled         = true
  ddns_update_interval = "15m"
}
