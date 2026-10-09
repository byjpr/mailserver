# Pure helpers shared by the NixOS modules and the Terraform variable export.
# Everything here is derived from settings.nix and the public DKIM keys in
# dkim/, so the server configuration and the DNS records always agree.
{ lib }:
let
  # Public DKIM keys live in dkim/<domain>/<selector>.txt and hold the full
  # TXT record value ("v=DKIM1; k=rsa; p=..."). They are written by
  # `just add-domain`. The private halves are in secrets/secrets.yaml.
  readDkimKeys =
    dkimDir:
    let
      domainDirs = lib.filterAttrs (_: type: type == "directory") (
        if builtins.pathExists dkimDir then builtins.readDir dkimDir else { }
      );
      selectorsOf =
        domain:
        lib.mapAttrs'
          (
            file: _:
            lib.nameValuePair (lib.removeSuffix ".txt" file) (
              lib.trim (builtins.readFile (dkimDir + "/${domain}/${file}"))
            )
          )
          (
            lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".txt" file) (
              builtins.readDir (dkimDir + "/${domain}")
            )
          );
    in
    lib.mapAttrs (domain: _: selectorsOf domain) domainDirs;
in
rec {
  mkContext =
    {
      settings,
      dkimDir,
      secretsFile,
    }:
    let
      fqdn = "${settings.hostname}.${settings.primaryDomain}";
      dkimKeys = readDkimKeys dkimDir;

      mtaStsPolicy = ''
        version: STSv1
        mode: ${settings.mtaSts.mode}
        mx: ${fqdn}
        max_age: 604800
      '';
      # The id must change whenever the policy changes (RFC 8461 3.1).
      mtaStsId = builtins.substring 0 20 (builtins.hashString "sha256" mtaStsPolicy);

      useSrs = settings.forwards != { };

      # Every address the server accepts mail for.
      addresses =
        lib.concatLists (
          lib.mapAttrsToList (name: acct: [ name ] ++ (acct.aliases or [ ])) settings.accounts
        )
        ++ lib.attrNames settings.forwards;

      domainOf = address: lib.last (lib.splitString "@" address);
    in
    {
      inherit
        secretsFile
        fqdn
        dkimKeys
        mtaStsPolicy
        mtaStsId
        useSrs
        addresses
        domainOf
        ;

      dnsRecords = dnsRecords {
        inherit
          settings
          fqdn
          dkimKeys
          mtaStsId
          domainOf
          ;
      };
    };

  # DNS records for every mail domain, excluding the A/AAAA records for the
  # mail host itself (Terraform adds those once it knows the droplet's IPs).
  # Names are relative to the zone ("@" is the zone apex).
  dnsRecords =
    {
      settings,
      fqdn,
      dkimKeys,
      mtaStsId,
      domainOf,
    }:
    let
      relayInclude = lib.optionalString (
        settings.relay.enable && settings.relay.spfInclude != ""
      ) " include:${settings.relay.spfInclude}";

      txt = domain: name: value: {
        inherit domain name value;
        type = "TXT";
      };

      # DMARC reports for one domain may only be sent to an address in
      # another domain if that domain explicitly authorises it (RFC 7489 7.1).
      reportDomain = domainOf settings.dmarc.reportAddress;

      forDomain =
        domain:
        [
          {
            inherit domain;
            type = "MX";
            name = "@";
            value = "${fqdn}.";
            priority = 10;
          }
          # Only the MX host (and the relay, if any) may send for this domain.
          (txt domain "@" "v=spf1 mx${relayInclude} -all")
          (txt domain "_dmarc" (
            lib.concatStringsSep "; " [
              "v=DMARC1"
              "p=${settings.dmarc.policy}"
              "sp=${settings.dmarc.policy}"
              "adkim=s"
              "aspf=s"
              "rua=mailto:${settings.dmarc.reportAddress}"
            ]
          ))
          (txt domain "_mta-sts" "v=STSv1; id=${mtaStsId}")
          (txt domain "_smtp._tls" "v=TLSRPTv1; rua=mailto:${settings.tlsReportAddress}")
          {
            inherit domain;
            type = "CNAME";
            name = "mta-sts";
            value = "${fqdn}.";
          }
          # RFC 6186 / 8314: let mail clients discover the implicit-TLS ports.
          {
            inherit domain;
            type = "SRV";
            name = "_submissions._tcp";
            value = "${fqdn}.";
            priority = 0;
            weight = 1;
            port = 465;
          }
          {
            inherit domain;
            type = "SRV";
            name = "_imaps._tcp";
            value = "${fqdn}.";
            priority = 0;
            weight = 1;
            port = 993;
          }
        ]
        ++ lib.mapAttrsToList (selector: value: txt domain "${selector}._domainkey" value) (
          dkimKeys.${domain} or { }
        )
        ++ lib.optional (domain != reportDomain) (txt reportDomain "${domain}._report._dmarc" "v=DMARC1");

      # Records for the mail host name itself, in the primary zone.
      hostName = settings.hostname;
      hostRecords = [
        # SPF for the HELO identity, checked on bounces (empty envelope sender).
        (txt settings.primaryDomain hostName "v=spf1 a -all")
        # Only Let's Encrypt may issue certificates for the mail host.
        {
          domain = settings.primaryDomain;
          type = "CAA";
          name = hostName;
          # Trailing dot: the DigitalOcean API stores CAA values that way.
          value = "letsencrypt.org.";
          flags = 0;
          tag = "issue";
        }
      ];
    in
    lib.concatMap forDomain settings.domains ++ hostRecords;
}
