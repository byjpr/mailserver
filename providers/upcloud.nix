# UpCloud cloud server. IPv4 comes from DHCP, IPv6 from router
# advertisements / DHCPv6, one virtio NIC per address.
{ ... }:
{
  mailserver.machine = {
    network.method = "dhcp";
  };
}
