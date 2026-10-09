# Mail stack: simple-nixos-mailserver (Postfix + Dovecot + Rspamd) wired up
# from settings.nix, with secrets from sops and extra anti-spoofing rules.
{
  config,
  lib,
  pkgs,
  settings,
  ctx,
  ...
}:
let
  inherit (ctx) fqdn dkimKeys domainOf;

  # Every mail domain (and the server's own name) is "ours": nobody may hand
  # us mail claiming to come from them on port 25 without authenticating.
  localSenderDomains = lib.unique (settings.domains ++ [ fqdn ]);

  dkimSecret = domain: selector: "dkim/${domain}/${selector}";
  mailboxSecret = address: "mailbox/${address}";

  inherit (ctx) secretsFile;
in
{
  # --- Secrets ----------------------------------------------------------------
  # Decrypted at activation with the server's SSH host key (converted to an age
  # key); see .sops.yaml. Nothing secret ever enters the world-readable store.
  sops = {
    # The fallback lets the CI example configuration evaluate without any
    # secrets; the real configuration asserts that the file exists (flake.nix).
    defaultSopsFile =
      if builtins.pathExists secretsFile then secretsFile else "/run/secrets.yaml-not-created";
    validateSopsFiles = builtins.pathExists secretsFile;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ];

    secrets =
      lib.mapAttrs' (
        address: _:
        lib.nameValuePair (mailboxSecret address) {
          key = "mailboxes/${address}";
          restartUnits = [ "dovecot.service" ];
        }
      ) settings.accounts
      // lib.listToAttrs (
        lib.concatMap (
          domain:
          lib.mapAttrsToList (
            selector: _:
            lib.nameValuePair (dkimSecret domain selector) {
              owner = config.services.rspamd.user;
              group = config.services.rspamd.group;
              restartUnits = [ "rspamd.service" ];
            }
          ) (dkimKeys.${domain} or { })
        ) settings.domains
      );
  };

  # --- Mail server ------------------------------------------------------------
  mailserver = {
    enable = true;
    stateVersion = 5;
    inherit fqdn;
    inherit (settings) domains forwards messageSizeLimit;
    systemDomain = settings.primaryDomain;
    systemContact = settings.adminEmail;

    x509.useACMEHost = fqdn;

    accounts = lib.mapAttrs (
      address: acct:
      {
        hashedPasswordFile = config.sops.secrets.${mailboxSecret address}.path;
      }
      // lib.filterAttrs (
        n: _:
        lib.elem n [
          "aliases"
          "catchAll"
          "quota"
          "sendOnly"
        ]
      ) acct
    ) settings.accounts;

    # Only implicit TLS: IMAPS 993 and submissions 465 (RFC 8314). Plain IMAP,
    # POP3 and STARTTLS submission stay disabled.
    enableImap = false;
    enableImapSsl = true;
    enablePop3 = false;
    enablePop3Ssl = false;
    enableSubmission = false;
    enableSubmissionSsl = true;
    enableManageSieve = false;

    # DKIM keys come from sops instead of being generated on the server, so
    # the public half can be published in DNS before the server exists.
    dkim.domains = lib.genAttrs settings.domains (domain: {
      selectors = lib.mapAttrs (selector: _: {
        keyFile = config.sops.secrets.${dkimSecret domain selector}.path;
      }) (dkimKeys.${domain} or { });
    });

    # Forwarded mail keeps passing SPF at the destination.
    srs.enable = ctx.useSrs;

    # Send aggregate DMARC and SMTP-TLS reports to other domains' operators.
    dmarcReporting.enable = true;
    tlsrpt.enable = true;

    # Don't leak the sender's client hostname in Message-IDs.
    rewriteMessageId = true;

    # ClamAV needs well over 1 GB of RAM; Rspamd still rejects known-bad
    # attachments and phishing via its own checks.
    virusScanning = false;
    fullTextSearch.enable = false;
  };

  # --- Postfix hardening on top of the module defaults -------------------------
  services.postfix.settings.main = {
    # Only the server itself may relay without authentication.
    mynetworks = [
      "127.0.0.0/8"
      "[::1]/128"
    ];

    # Port 25 is for server-to-server mail only. Authentication is offered
    # exclusively on the submissions port (465), which overrides this.
    smtpd_sasl_auth_enable = lib.mkForce false;

    smtpd_helo_required = true;
    smtpd_helo_restrictions = [
      "permit_mynetworks"
      "reject_invalid_helo_hostname"
      "reject_non_fqdn_helo_hostname"
    ];

    smtpd_sender_restrictions = [
      "permit_mynetworks"
      "reject_non_fqdn_sender"
      "reject_unknown_sender_domain"
      # Unauthenticated mail claiming to be from one of our own domains is
      # spoofed by definition: all of our users send through port 465.
      "check_sender_access hash:/var/lib/postfix/conf/local_sender_domains"
    ];

    smtpd_recipient_restrictions = [
      "reject_non_fqdn_recipient"
      "reject_unknown_recipient_domain"
      "reject_unauth_pipelining"
    ];
    smtpd_data_restrictions = [ "reject_unauth_pipelining" ];

    # Slow down password guessing on the submission port (per client IP/min).
    smtpd_client_auth_rate_limit = 10;

    # Record the TLS version and cipher in Received headers.
    smtpd_tls_received_header = true;
  };

  services.postfix.mapFiles."local_sender_domains" = pkgs.writeText "local_sender_domains" (
    lib.concatMapStrings (
      domain:
      "${domain} REJECT 5.7.1 Sender address belongs to this server; authenticate on port 465 to send\n"
    ) localSenderDomains
  );

  # --- Rspamd -----------------------------------------------------------------
  # Authenticated users may only use their own addresses in the From: header
  # (Postfix only enforces this for the envelope sender).
  services.rspamd.localLuaRules =
    let
      allowed = builtins.toJSON (
        lib.mapAttrs (address: acct: {
          addresses = [ address ] ++ (acct.aliases or [ ]);
          regexes = acct.aliasesRegexp or [ ];
        }) settings.accounts
      );
    in
    assert lib.assertMsg (!lib.hasInfix "]==]" allowed) "account addresses may not contain ]==]";
    pkgs.writeText "rspamd.local.lua" (
      builtins.replaceStrings [ "@ALLOWED@" ] [ allowed ] (builtins.readFile ./rspamd/from-owner.lua)
    );

  services.rspamd.locals = {
    # Enforce the sender's published DMARC policy instead of only scoring it.
    # This is what stops spoofed mail claiming to be from paypal.com & co.
    "dmarc.conf".text = ''
      actions {
        reject = "reject";
        quarantine = "add header";
      }
    '';

    # Mail to forwarded addresses leaves again from our IP. Spam that would
    # normally only be marked ("add header") is rejected instead, so we never
    # pass it on to Gmail & co. under our own reputation. Rejecting during
    # SMTP leaves the bounce to the sending server: no backscatter.
    "settings.conf".text = lib.optionalString (settings.forwards != { }) ''
      forwarded_recipients {
        priority = high;
        rcpt = ${builtins.toJSON (lib.attrNames settings.forwards)};
        apply {
          actions {
            reject = ${toString settings.forwardRejectScore};
            "add header" = null;
            "rewrite subject" = null;
          }
        }
      }
    '';

    # Cap how much mail one authenticated account can send, so a leaked
    # password can't turn the server into a spam cannon (and get its IP
    # blocklisted).
    "ratelimit.conf".text = ''
      rates {
        user {
          bucket {
            burst = ${toString settings.outboundRateLimit.burst};
            rate = "${settings.outboundRateLimit.perUser}";
          }
        }
      }
    '';
  };

  # --- Sanity checks ----------------------------------------------------------
  assertions =
    let
      addressDomains = map domainOf ctx.addresses;
    in
    [
      {
        assertion = lib.elem settings.primaryDomain settings.domains;
        message = "settings.nix: primaryDomain (${settings.primaryDomain}) must be listed in `domains`.";
      }
      {
        assertion = lib.elem (domainOf settings.dmarc.reportAddress) settings.domains;
        message = "settings.nix: dmarc.reportAddress must be an address in one of your `domains`.";
      }
    ]
    ++ map (domain: {
      assertion = lib.elem "postmaster@${domain}" ctx.addresses;
      message = "settings.nix: no mailbox, alias or forward for postmaster@${domain} (required by RFC 5321/2142).";
    }) settings.domains
    ++ map (domain: {
      assertion = (dkimKeys.${domain} or { }) != { };
      message = "No DKIM key for ${domain}. Run `just add-domain ${domain}`.";
    }) settings.domains
    ++ map (domain: {
      assertion = lib.elem domain settings.domains;
      message = "settings.nix: an address uses the domain ${domain}, which is not listed in `domains`.";
    }) (lib.unique addressDomains);
}
