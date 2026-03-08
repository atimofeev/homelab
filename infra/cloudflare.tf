data "cloudflare_zone" "this" {
  filter {
    name   = var.domain
    status = "active"
    paused = false
  }
}

resource "cloudflare_dns_record" "routeros_ddns" {
  zone_id = data.cloudflare_zone.this.zone_id
  name    = "homelab-ingress.${var.dns_zone_name}"
  ttl     = 1
  type    = "CNAME"
  comment = "RouterOS Cloud DDNS name"
  content = data.routeros_ip_cloud.this.dns_name
  proxied = false
}

