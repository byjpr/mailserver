# OVHcloud VPS for the mail host.
#
# Port 25 is open on OVHcloud VPS (not on Public Cloud, and never in "Local
# Zone" (.LZ) plans). OVH monitors outgoing mail and blocks port 25 for an IP
# that sends spam.
#
# Creating the VPS places a paid order on your account (default payment
# method required); `tofu destroy` would terminate it, which the lifecycle
# guard below prevents.

terraform {
  required_version = ">= 1.6"
  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.22"
    }
  }
}

# Credentials from the environment: OVH_ENDPOINT (e.g. ovh-eu) plus either
# OVH_APPLICATION_KEY / OVH_APPLICATION_SECRET / OVH_CONSUMER_KEY or
# OVH_CLIENT_ID / OVH_CLIENT_SECRET. See README.
provider "ovh" {}

variable "mail" {
  description = "Generated from settings.nix by `just apply`. Do not edit by hand."
  type        = any
}

variable "dns_ready" {
  description = "Set by `just apply` once the A/AAAA records exist; OVH refuses a reverse DNS entry whose forward record does not point back."
  type        = bool
  default     = false
}

locals {
  m = var.mail
}

data "ovh_me" "me" {}

resource "ovh_vps" "mail" {
  ovh_subsidiary       = data.ovh_me.me.ovh_subsidiary
  display_name         = local.m.fqdn
  do_not_send_password = true

  plan = [{
    duration     = "P1M"
    plan_code    = local.m.server.plan
    pricing_mode = "default"
    configuration = [
      { label = "vps_datacenter", value = local.m.server.location },
      { label = "vps_os", value = local.m.server.image },
    ]
  }]

  lifecycle {
    # Changing these would order a new VPS and terminate the one with all mail.
    ignore_changes = [plan, image_id, public_ssh_key, do_not_send_password]
    # Remove this line deliberately if you really want to terminate the server.
    prevent_destroy = true
  }
}

# Reinstall the freshly ordered VPS with your SSH key, so `just install` can
# log in. (The image ID needed for this only exists once the VPS does.)
resource "terraform_data" "ssh_access" {
  triggers_replace = [ovh_vps.mail.service_name]

  provisioner "local-exec" {
    command = "python3 ${path.module}/../../../scripts/ovh-vps-rebuild.py"
    environment = {
      VPS_SERVICE_NAME = ovh_vps.mail.service_name
      VPS_IMAGE_NAME   = local.m.server.image
      VPS_SSH_KEY      = local.m.sshKeys[0]
    }
  }
}

data "ovh_vps" "mail" {
  service_name = ovh_vps.mail.service_name
  depends_on   = [terraform_data.ssh_access]
}

locals {
  ipv4 = one([for ip in data.ovh_vps.mail.ips : ip if !strcontains(ip, ":")])
  ipv6 = one([for ip in data.ovh_vps.mail.ips : ip if strcontains(ip, ":")])
}

resource "ovh_ip_reverse" "mail" {
  for_each = var.dns_ready ? { ipv4 = "${local.ipv4}/32", ipv6 = "${local.ipv6}/128" } : {}

  ip                         = each.value
  ip_reverse                 = split("/", each.value)[0]
  reverse                    = "${local.m.fqdn}."
  readiness_timeout_duration = "10m"
}

output "ipv4" {
  value = local.ipv4
}

output "ipv6" {
  value = local.ipv6
}
