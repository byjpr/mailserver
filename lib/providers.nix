# What differs between hosting providers, outside of their Terraform step
# (infra/servers/<name>) and NixOS module (providers/<name>.nix).
{
  ovh = {
    # Stock image user that nixos-anywhere logs in as (uses sudo if not root).
    installUser = "debian";
    hasIPv6 = true;
    # OVH checks that the A/AAAA records point back before accepting a PTR.
    reverseDnsNeedsForwardDns = true;
    afterApply = "";
  };
  netcup = {
    installUser = "root";
    hasIPv6 = true;
    reverseDnsNeedsForwardDns = false;
    afterApply = "";
  };
  upcloud = {
    installUser = "root";
    hasIPv6 = true;
    reverseDnsNeedsForwardDns = false;
    afterApply = "UpCloud blocks outbound port 25 until Support lifts it: open a ticket (they ask for ID and your use case), or set relay.enable in settings.nix.";
  };
  serverspace = {
    installUser = "root";
    hasIPv6 = false;
    reverseDnsNeedsForwardDns = false;
    afterApply = "Serverspace sets reverse DNS only by support ticket: ask for {ipv4} -> {fqdn}, and ask them to confirm outbound port 25 is open.";
  };
  digitalocean = {
    installUser = "root";
    hasIPv6 = true;
    reverseDnsNeedsForwardDns = false;
    afterApply = "DigitalOcean blocks outbound port 25: make sure relay.enable is set in settings.nix.";
  };
}
