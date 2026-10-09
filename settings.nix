# ---------------------------------------------------------------------------
# This is the only file you normally need to edit.
#
# Both the NixOS configuration (flake.nix -> modules/) and the Terraform
# infrastructure (terraform/, via `just tfvars`) are generated from it, so
# domains, mailboxes and DNS can never drift apart.
#
# After editing:
#   just plan / just apply   -> infrastructure + DNS records
#   just deploy              -> push the new NixOS configuration to the server
# ---------------------------------------------------------------------------
{
  # The mail server's own name is "<hostname>.<primaryDomain>", e.g.
  # mail.example.com. It is used for the MX target, the TLS certificate, the
  # SMTP banner/HELO and the reverse DNS (PTR) record of the droplet.
  hostname = "mail";
  primaryDomain = "example.com";

  # Every domain this server receives and sends mail for. Each one needs a
  # DKIM key: run `just add-domain <domain>` after adding it here.
  domains = [
    "example.com"
  ];

  # Mailboxes. Set or change a password with `just passwd <address>`; the
  # password hash is stored encrypted in secrets/secrets.yaml, never here.
  #
  # Options per mailbox (all optional):
  #   aliases  = extra addresses delivered to this mailbox (and which this
  #              mailbox is allowed to send as)
  #   catchAll = domains for which unknown addresses land in this mailbox
  #              (not recommended: catch-alls attract a lot of spam)
  #   quota    = e.g. "5G"
  #   sendOnly = true for accounts that only send (apps, notifications)
  #
  # RFC 2142 requires postmaster@ and abuse@ for every domain; the build
  # fails if a domain is missing a postmaster@ address.
  accounts = {
    "admin@example.com" = {
      aliases = [
        "postmaster@example.com"
        "abuse@example.com"
        "hostmaster@example.com"
        # Aggregate DMARC and TLS reports from other providers arrive here.
        "dmarc-reports@example.com"
        "tls-reports@example.com"
      ];
      quota = "5G";
    };

    # "notifications@example.com" = {
    #   sendOnly = true;
    # };
  };

  # Forward addresses to external mailboxes:
  #   "someone@example.com" = "someone@gmail.com";
  # Forwarding breaks SPF; Sender Rewriting Scheme (SRS) is turned on
  # automatically when forwards exist, so forwarded mail still passes.
  forwards = { };

  # Contact address published in DMARC/TLS-RPT reports and used for the
  # Let's Encrypt account.
  adminEmail = "admin@example.com";

  # SSH public keys allowed to log in as root (key auth only; passwords are
  # disabled). These are also uploaded to DigitalOcean for the first boot.
  sshKeys = [
    # "ssh-ed25519 AAAA... you@laptop"
  ];

  # Restrict SSH to these networks at the DigitalOcean cloud firewall. Mail
  # ports are always open to the world. Narrow this if you have a static IP.
  sshAllowedCidrs = [
    "0.0.0.0/0"
    "::/0"
  ];

  dmarc = {
    # "reject" is right for domains that only send mail through this server.
    # Use "quarantine" or "none" while migrating a domain that also sends
    # from elsewhere (e.g. a newsletter service you have not authorised yet).
    policy = "reject";
    # Where other providers send aggregate DMARC reports.
    reportAddress = "dmarc-reports@example.com";
  };

  # SMTP TLS reporting (RFC 8460) address.
  tlsReportAddress = "tls-reports@example.com";

  # MTA-STS (RFC 8461) makes other servers require valid TLS when delivering
  # to you. Use "testing" while you set things up, then "enforce".
  mtaSts.mode = "enforce";

  # Outbound relay ("smarthost"). DigitalOcean blocks outbound port 25 on
  # new accounts; ask support to lift it, or send through a relay instead.
  # Put the relay password in the secrets with `just relay-password`.
  relay = {
    enable = false;
    host = "smtp.postmarkapp.com"; # or email-smtp.<region>.amazonaws.com, smtp.mailgun.org, ...
    port = 587;
    username = "";
    # Added to every domain's SPF record, e.g. "spf.mtasv.net" (Postmark),
    # "amazonses.com" (SES), "mailgun.org" (Mailgun).
    spfInclude = "";
  };

  # Limit how much a single (possibly compromised) account can send.
  # Format understood by rspamd's ratelimit module.
  outboundRateLimit = {
    perUser = "200 / 1h";
    burst = 50;
  };

  # Messages larger than this are rejected (bytes). 25 MiB.
  messageSizeLimit = 26214400;

  # Pull and apply this flake from git every night (security updates). Only
  # works once the repo is pushed somewhere the server can read; for a private
  # GitHub repo, use "git+ssh://..." with a deploy key, or leave this off and
  # run `just update && just deploy` yourself.
  autoUpgrade = {
    enable = false;
    flake = "github:your-user/mailserver";
  };

  timeZone = "UTC";

  # DigitalOcean droplet. s-1vcpu-1gb is the smallest size that comfortably
  # runs Postfix + Dovecot + Rspamd + Redis (virus scanning is disabled;
  # ClamAV alone needs >1 GB).
  droplet = {
    region = "fra1";
    size = "s-1vcpu-1gb";
    # Weekly droplet snapshots (+20% of droplet price). Your mail lives on
    # this disk, so keep this on unless you have your own backups.
    backups = true;
  };

  # Manage all DNS records with Terraform in DigitalOcean DNS. Set to false
  # if your DNS is hosted elsewhere; `just dns` then prints the records.
  manageDns = true;
}
