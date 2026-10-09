# Optional outbound relay ("smarthost"), for when direct delivery on port 25
# is blocked by the hosting provider or you want a relay's IP reputation.
{
  config,
  lib,
  settings,
  ...
}:
let
  cfg = settings.relay;
  nexthop = "[${cfg.host}]:${toString cfg.port}";
in
lib.mkIf cfg.enable {
  sops.secrets."relay/password" = { };

  # Postfix's smtp client opens this map at startup, normally before it
  # drops privileges. Group-readable by postfix (never world-readable) so it
  # also works if the table is (re)opened as the postfix user.
  sops.templates."postfix-relay-credentials" = {
    content = "${nexthop} ${cfg.username}:${config.sops.placeholder."relay/password"}\n";
    owner = "root";
    group = config.services.postfix.group;
    mode = "0440";
    restartUnits = [ "postfix.service" ];
  };

  # All outbound mail goes to one known host, so per-destination DANE/MTA-STS
  # lookups do not apply; instead the relay's certificate must verify.
  services.postfix-tlspol.enable = lib.mkForce false;
  services.postfix-tlspol.configurePostfix = lib.mkForce false;

  services.postfix.settings.main = {
    relayhost = [ nexthop ];
    smtp_sasl_auth_enable = true;
    smtp_sasl_password_maps = "texthash:${config.sops.templates."postfix-relay-credentials".path}";
    smtp_sasl_security_options = "noanonymous";
    smtp_sasl_tls_security_options = "noanonymous";
    # Never send the relay password unencrypted or to an impostor.
    smtp_tls_security_level = lib.mkForce "secure";
    smtp_tls_policy_maps = lib.mkForce [ ];
    # Port 465 uses implicit TLS instead of STARTTLS.
    smtp_tls_wrappermode = cfg.port == 465;
  };

  assertions = [
    {
      assertion = cfg.username != "";
      message = "settings.nix: relay.enable is set but relay.username is empty.";
    }
  ];
}
