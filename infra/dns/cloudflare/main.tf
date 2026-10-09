# DNS records for all mail domains in Cloudflare.
#
# The zones must already exist in your Cloudflare account (add the domain in
# the dashboard and point its NS records at Cloudflare). This only manages
# the records listed in settings.nix-derived variables; other records in the
# zones are left alone.

terraform {
  required_version = ">= 1.6"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.27"
    }
  }
}

# Reads the API token from CLOUDFLARE_API_TOKEN. It needs "Zone:DNS:Edit"
# and "Zone:Zone:Read" for the mail domains.
provider "cloudflare" {}

variable "mail" {
  description = "Generated from settings.nix by `just tfvars`."
  type        = any
}

variable "server" {
  description = "Public addresses of the server, written by `just apply` from the server step."
  type = object({
    ipv4 = string
    ipv6 = string
  })
}

data "cloudflare_zone" "mail" {
  for_each = toset(var.mail.domains)
  filter   = { name = each.value }
}

locals {
  host_records = [
    for type, ip in { A = var.server.ipv4, AAAA = var.server.ipv6 } : {
      domain   = var.mail.primaryDomain
      type     = type
      name     = var.mail.hostname
      value    = ip
      priority = null
      weight   = null
      port     = null
      flags    = null
      tag      = null
    } if ip != ""
  ]

  records = {
    for r in concat(local.host_records, var.mail.dnsRecords) :
    "${r.domain} ${r.type} ${r.name}" => r
  }
}

resource "cloudflare_dns_record" "mail" {
  for_each = local.records

  zone_id = data.cloudflare_zone.mail[each.value.domain].id
  name    = each.value.name == "@" ? each.value.domain : "${each.value.name}.${each.value.domain}"
  type    = each.value.type
  ttl     = 3600
  # Mail must never go through Cloudflare's HTTP proxy.
  proxied = false

  # MX, CNAME, TXT, A and AAAA use `content`; SRV and CAA use `data`.
  content = contains(["SRV", "CAA"], each.value.type) ? null : trimsuffix(each.value.value, ".")
  priority = each.value.type == "MX" ? each.value.priority : null

  data = contains(["SRV", "CAA"], each.value.type) ? {
    priority = each.value.type == "SRV" ? each.value.priority : null
    weight   = each.value.type == "SRV" ? each.value.weight : null
    port     = each.value.type == "SRV" ? each.value.port : null
    target   = each.value.type == "SRV" ? trimsuffix(each.value.value, ".") : null
    flags    = each.value.type == "CAA" ? each.value.flags : null
    tag      = each.value.type == "CAA" ? each.value.tag : null
    value    = each.value.type == "CAA" ? each.value.value : null
  } : null
}
