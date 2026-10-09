# netcup VPS / root server for the mail host.
#
# netcup servers cannot be created through an API: order one in the shop
# (VPS nano G11.5s or larger; 2 GB RAM is the practical minimum for the
# installer) and put its server ID (SCP -> server -> "General") into
# settings.server.serverId. This step then adopts the server:
#   - sets its host name and the reverse DNS of the IPv4 and IPv6 addresses
#   - turns off netcup's network firewall, whose default "netcup Mail block"
#     policy blocks SMTP in both directions (nftables on the host filters
#     traffic instead)
#   - exports the static network configuration (netcup does not announce
#     IPv6 via router advertisements, and DHCPv4 is not reliable on all
#     generations)

terraform {
  required_version = ">= 1.6"
  required_providers {
    netcup = {
      source  = "rixlhq/netcup"
      version = "~> 1.2"
    }
  }
}

# Reads the SCP refresh token from NETCUP_SCP_REFRESH_TOKEN. Get one with
# `just netcup-login` (OAuth device flow; it stays valid while used at least
# once every 30 days).
provider "netcup" {}

variable "mail" {
  description = "Generated from settings.nix by `just apply`. Do not edit by hand."
  type        = any
}

locals {
  m         = var.mail
  server_id = local.m.server.serverId
}

data "netcup_scp_server" "mail" {
  server_id = local.server_id
}

data "netcup_scp_server_interfaces" "mail" {
  server_id = local.server_id
}

locals {
  nic = one([
    for i in data.netcup_scp_server_interfaces.mail.scp_server_interfaces : i
    if length(i.ipv4addresses) > 0
  ])
  v4 = data.netcup_scp_server.mail.ipv4addresses[0]
  v6 = data.netcup_scp_server.mail.ipv6addresses[0]

  # 255.255.252.0 -> 22
  v4_prefix = length(regexall("1", join("", [
    for octet in split(".", local.v4.netmask) : format("%08b", tonumber(octet))
  ])))
  # The server gets a whole /64; use the first address in it.
  v6_address = cidrhost("${split("/", local.v6.network_prefix)[0]}/${local.v6.network_prefix_length}", 1)
}

resource "netcup_scp_server" "mail" {
  server_id = local.server_id
  hostname  = local.m.fqdn
  nickname  = local.m.fqdn
}

resource "netcup_scp_server_interface_firewall" "mail" {
  server_id         = local.server_id
  mac               = local.nic.mac
  active            = false
  copied_policy_ids = []
  user_policy_ids   = []
}

resource "netcup_scp_rdns" "ipv4" {
  ip_version = "ipv4"
  ip         = local.v4.ip
  rdns       = local.m.fqdn
}

resource "netcup_scp_rdns" "ipv6" {
  ip_version = "ipv6"
  ip         = local.v6_address
  rdns       = local.m.fqdn
}

output "ipv4" {
  value = local.v4.ip
}

output "ipv6" {
  value = local.v6_address
}

# Written to network.json by `just apply`; NixOS configures it statically.
output "network" {
  value = {
    ipv4 = {
      address      = local.v4.ip
      prefixLength = local.v4_prefix
      gateway      = local.v4.gateway
    }
    ipv6 = {
      address      = local.v6_address
      prefixLength = local.v6.network_prefix_length
      gateway      = coalesce(local.v6.gateway, "fe80::1")
    }
  }
}
