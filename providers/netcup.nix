# netcup VPS / root server. IPv6 is never announced and DHCPv4 is not
# reliable on all generations, so addresses are configured statically from
# machine.json (recorded by `just install`, using the addresses the netcup
# Terraform step reads from the Server Control Panel).
{ ... }:
{
  mailserver.machine.network.method = "static";
}
