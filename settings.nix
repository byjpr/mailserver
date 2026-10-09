# ---------------------------------------------------------------------------
# This is the only file you normally need to edit.
#
# Both the NixOS configuration (flake.nix -> modules/) and the Terraform
# infrastructure (infra/, written by `just apply`) are generated from it, so
# domains, mailboxes and DNS can never drift apart.
#
# After editing:
#   just plan / just apply   -> infrastructure + DNS records
#   just deploy              -> push the new NixOS configuration to the server
# ---------------------------------------------------------------------------
{
  # The mail server's own name is "<hostname>.<primaryDomain>", e.g.
  # mail.example.com. It is used for the MX target, the TLS certificate, the
  # SMTP banner/HELO and the reverse DNS (PTR) record of the server.
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
  # disabled). The first one is also given to the provider for the initial
  # login before NixOS is installed.
  sshKeys = [
    # "ssh-ed25519 AAAA... you@laptop"
  ];

  # Only accept SSH from these networks (enforced by the host firewall).
  # Mail ports are always open to the world. Narrow this if you have a
  # static IP or a VPN.
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

  # Outbound relay ("smarthost"), for providers that block outbound port 25
  # or while a new IP builds reputation. Put the relay password in the
  # secrets with `just relay-password`.
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

  # Hourly self-check: services, TLS certificate, disk, mail queue, outbound
  # SMTP and blocklists. Create a check at https://healthchecks.io (free) or
  # your own Healthchecks / Uptime Kuma "push" monitor with a 1 hour period,
  # and paste its ping URL here: you are then alerted when a check fails AND
  # when the server stops reporting (e.g. because it is down). Without a URL,
  # problems are mailed to adminEmail, which can't work if mail is broken.
  monitoring = {
    healthcheckUrl = ""; # e.g. "https://hc-ping.com/<uuid>"
    diskWarnPercent = 85;
    queueWarn = 100;
  };

  timeZone = "UTC";

  # Where the server runs. Each provider has a Terraform step in
  # infra/servers/<provider> and notes in docs/providers.md.
  #
  #   "ovh"          OVHcloud VPS. Port 25 open by default. Recommended.
  #   "netcup"       netcup VPS/root server. Order it manually, then set
  #                  server.netcup.serverId. Port 25 opened automatically.
  #   "upcloud"      UpCloud. Port 25 blocked until Support lifts it.
  #   "serverspace"  Serverspace vStack. IPv4 only; PTR and port 25 by ticket.
  #   "digitalocean" DigitalOcean. Port 25 blocked; only usable with `relay`.
  provider = "ovh";

  # Size and location per provider; only the selected provider's entry is
  # used. 2 GB of RAM is the minimum the installer (nixos-anywhere) needs.
  server = {
    ovh = {
      plan = "vps-2027-model1"; # 2 vCPU, 4 GB, 40 GB; about 4.50 EUR/month
      # GRA, SBG, RBX ("EU-WEST-RBX"), DE, UK, WAW, BHS, SGP, SYD, ...
      location = "GRA";
      image = "Debian 13"; # only used until `just install` replaces it
    };
    netcup = {
      # SCP -> your server -> "General" -> server ID (a number).
      serverId = 0;
    };
    upcloud = {
      plan = "STARTER-1xCPU-2GB"; # 1 vCPU, 2 GB, 20 GB; about 6 EUR/month
      location = "de-fra1"; # fi-hel1, nl-ams1, uk-lon1, se-sto1, ...
      diskSize = 20; # GB
      backups = true; # daily, kept 7 days (billed per GB)
    };
    serverspace = {
      location = "nj3"; # `just apply` lists valid ids if this one is wrong
      image = "Debian-12-X64";
      cpu = 1;
      ramMB = 2048;
      diskSize = 25; # GB
      bandwidthMbps = 50;
    };
    digitalocean = {
      region = "fra1";
      size = "s-1vcpu-2gb";
      backups = true;
    };
  };

  # Where the DNS records for your domains are created.
  #   "cloudflare"  by Terraform (zones must already exist in Cloudflare)
  #   "manual"      `just dns` prints them for you to enter anywhere
  dns = "cloudflare";
}
