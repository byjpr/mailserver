# DigitalOcean droplet. DigitalOcean blocks outbound port 25 on most
# accounts, so this provider only makes sense together with settings.relay.
{ ... }:
{
  mailserver.machine = {
    # Public addresses come from the metadata service, not DHCP/SLAAC.
    network = {
      method = "cloud-init";
      cloudInitDatasource = "DigitalOcean";
    };
  };

  # Metrics and alerting in the DigitalOcean control panel.
  services.do-agent.enable = true;
}
