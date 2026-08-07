data "cloudflare_zone" "this" {
  filter = {
    name   = var.domain
    status = "active"
  }
}

data "cloudflare_account_members" "accepted" {
  account_id = data.cloudflare_zone.this.account.id
  status     = "accepted"
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

resource "cloudflare_notification_policy" "r2_storage" {
  account_id = data.cloudflare_zone.this.account.id
  name       = "R2 storage approaching free-tier limit"
  alert_type = "billing_usage_alert"
  enabled    = true

  mechanisms = {
    email = [
      for member in data.cloudflare_account_members.accepted.result : {
        id = member.email
      }
    ]
  }

  filters = {
    product = ["r2_storage"]
    limit   = [tostring(9 * 1024 * 1024 * 1024)]
  }
}
