# TLS certificates (Let's Encrypt) and the MTA-STS policy endpoints.
#
# nginx is the only web server and serves nothing but:
#   - ACME HTTP-01 challenges for <fqdn> and mta-sts.<domain>
#   - https://mta-sts.<domain>/.well-known/mta-sts.txt
# Everything else gets a closed connection.
{
  lib,
  pkgs,
  settings,
  ctx,
  ...
}:
let
  policyFile = pkgs.writeText "mta-sts.txt" ctx.mtaStsPolicy;
  hsts = ''add_header Strict-Transport-Security "max-age=31536000" always;'';
in
{
  security.acme = {
    acceptTerms = true;
    defaults.email = settings.adminEmail;
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  services.nginx = {
    enable = true;
    serverTokens = false;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;

    virtualHosts = {
      # The mail host itself only needs a certificate for Postfix/Dovecot.
      ${ctx.fqdn} = {
        enableACME = true;
        addSSL = true;
        locations."/".return = "404";
        extraConfig = hsts;
      };

      # Anything not addressed to a known name: drop the connection.
      "_" = {
        default = true;
        rejectSSL = true;
        locations."/".return = "444";
      };
    }
    // lib.listToAttrs (
      map (
        domain:
        lib.nameValuePair "mta-sts.${domain}" {
          enableACME = true;
          forceSSL = true;
          locations."= /.well-known/mta-sts.txt" = {
            alias = policyFile;
            extraConfig = ''
              default_type text/plain;
              ${hsts}
            '';
          };
          locations."/".return = "404";
          extraConfig = hsts;
        }
      ) settings.domains
    );
  };
}
