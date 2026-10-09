# OVHcloud VPS. IPv4 would also work via DHCP, but the IPv6 /128 must be
# configured statically (on-link gateway), so both are taken from
# machine.json, which `just install` records from the stock image.
{ ... }:
{
  mailserver.machine.network.method = "static";
}
