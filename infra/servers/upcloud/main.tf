# UpCloud server for the mail host.
#
# UpCloud blocks outbound port 25 on every account until Support lifts it
# (they ask for identification and your use case). Until then, use
# settings.relay. See https://upcloud.com/docs/guides/sending-email-smtp-best-practices/

terraform {
  required_version = ">= 1.6"
  required_providers {
    upcloud = {
      source  = "UpCloudLtd/upcloud"
      version = "~> 5.46"
    }
  }
}

# Credentials: UPCLOUD_USERNAME + UPCLOUD_PASSWORD (an API sub-account is
# recommended), or UPCLOUD_TOKEN.
provider "upcloud" {}

variable "mail" {
  description = "Generated from settings.nix by `just apply`. Do not edit by hand."
  type        = any
}

locals {
  m = var.mail
}

resource "upcloud_server" "mail" {
  hostname = local.m.fqdn
  title    = local.m.fqdn
  zone     = local.m.server.location
  plan     = local.m.server.plan
  # Needed by the cloud-init based templates (and only used by the initial
  # Debian image; NixOS does not read it).
  metadata = true
  # Filtering is done by nftables on the host. UpCloud's network firewall is
  # stateless, so every reply packet would need its own rule; the risk of
  # locking out DHCP/IPv6 router advertisements outweighs a second layer.
  firewall = false

  # Only the starting point; `just install` replaces it with NixOS.
  template {
    storage = "Debian GNU/Linux 12 (Bookworm)"
    size    = local.m.server.diskSize
    # Daily disk backups kept for a week (billed per GB by UpCloud).
    dynamic "backup_rule" {
      for_each = local.m.server.backups ? [1] : []
      content {
        interval  = "daily"
        time      = "0300"
        retention = 7
      }
    }
  }

  # UpCloud attaches one NIC per public address.
  network_interface {
    type = "public"
  }
  network_interface {
    type              = "public"
    ip_address_family = "IPv6"
  }

  login {
    user            = "root"
    keys            = local.m.sshKeys
    create_password = false
  }

  lifecycle {
    # Changing these would rebuild the server and destroy all mail.
    ignore_changes = [template, login, metadata]
    # Remove this line deliberately if you really want to destroy the server.
    prevent_destroy = true
  }
}

locals {
  ipv4 = upcloud_server.mail.network_interface[0].ip_address
  ipv6 = upcloud_server.mail.network_interface[1].ip_address
}

# Reverse DNS. The Terraform provider cannot set PTR records, so call the API
# directly. Re-runs whenever an address or the host name changes.
resource "terraform_data" "ptr" {
  for_each         = { ipv4 = local.ipv4, ipv6 = local.ipv6 }
  triggers_replace = [each.value, local.m.fqdn]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      if [[ -n "$${UPCLOUD_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer $UPCLOUD_TOKEN")
      else
        auth=(-u "$UPCLOUD_USERNAME:$UPCLOUD_PASSWORD")
      fi
      curl -fsS -X PATCH "$${auth[@]}" -H 'Content-Type: application/json' \
        "https://api.upcloud.com/1.3/ip_address/${each.value}" \
        -d '{"ip_address":{"ptr_record":"${local.m.fqdn}"}}' > /dev/null
    EOT
  }
}

output "ipv4" {
  value = local.ipv4
}

output "ipv6" {
  value = local.ipv6
}
