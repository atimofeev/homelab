data "cloudflare_zone" "this" {
  filter = {
    name   = var.domain
    status = "active"
  }
}

resource "cloudflare_dns_record" "routeros_ddns" {
  zone_id = data.cloudflare_zone.this.id
  name    = "homelab-ingress.${var.domain}"
  ttl     = 1
  type    = "CNAME"
  comment = "RouterOS Cloud DDNS name"
  content = routeros_ip_cloud.this.dns_name
  proxied = false
}

