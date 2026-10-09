# Serverspace (vStack cloud) server for the mail host.
#
# Limitations of this provider, all handled outside Terraform:
#   - No public IPv6: the server is IPv4-only (no AAAA record is published).
#   - Reverse DNS (PTR) can only be set by a support ticket: ask for
#     <ipv4> -> <fqdn> after `just apply`.
#   - Port 25 "may be restricted at the network level"; test it and open a
#     ticket, or use settings.relay.
#   - No firewall for vStack servers; nftables on the host is the only filter.

terraform {
  required_version = ">= 1.6"
  required_providers {
    serverspace = {
      source  = "itglobalcom/serverspace"
      version = "~> 0.3.2"
    }
  }
}

# Reads the project API key from SERVERSPACE_KEY (panel -> Automation).
provider "serverspace" {}

variable "mail" {
  description = "Generated from settings.nix by `just tfvars`. Do not edit by hand."
  type        = any
}

locals {
  m = var.mail
}

resource "serverspace_ssh" "admin" {
  for_each   = { for i, k in local.m.sshKeys : tostring(i) => k }
  name       = "${local.m.fqdn}-${each.key}"
  public_key = each.value
}

resource "serverspace_server" "mail" {
  name     = replace(local.m.fqdn, ".", "-")
  location = local.m.server.location
  # Only the starting point; `just install` replaces it with NixOS. List the
  # current image IDs with:
  #   curl -H "X-API-KEY: $SERVERSPACE_KEY" https://api.serverspace.io/api/v1/images
  image            = local.m.server.image
  cpu              = local.m.server.cpu
  ram              = local.m.server.ramMB
  boot_volume_size = local.m.server.diskSize * 1024

  nic {
    network      = ""
    network_type = "PublicShared"
    bandwidth    = local.m.server.bandwidthMbps
  }

  ssh_keys = [for k in serverspace_ssh.admin : tonumber(k.id)]

  lifecycle {
    # Changing these would rebuild the server and destroy all mail.
    ignore_changes = [image, ssh_keys]
    # Remove this line deliberately if you really want to destroy the server.
    prevent_destroy = true
  }
}

output "ipv4" {
  value = serverspace_server.mail.public_ip_addresses[0]
}

output "ipv6" {
  value = ""
}
