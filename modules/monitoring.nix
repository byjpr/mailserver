# Hourly self-check of the mail server, reported to an external
# "dead man's switch" (healthchecks.io, a self-hosted Healthchecks or Uptime
# Kuma push monitor, ...). The external service alerts you when a check
# fails AND when reports stop arriving, so it also catches the server being
# down entirely, which no check running on the server itself can.
#
# Without monitoring.healthcheckUrl, failures are mailed to adminEmail
# instead (at most once a day), which only works while the server can still
# send mail.
{
  lib,
  pkgs,
  settings,
  ctx,
  ...
}:
let
  cfg = settings.monitoring;
  stateDir = "/var/lib/mail-health";
in
{
  systemd.services.mail-health-check = {
    description = "Mail server health check";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      bash
      coreutils
      curl
      dig
      gawk
      gnugrep
      openssl
      postfix
      systemd
      util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "mail-health";
    };
    script = ''
      set -u
      problems=()
      problem() { problems+=("$*"); echo "PROBLEM: $*" >&2; }

      # 1. Services
      for unit in postfix dovecot rspamd redis-rspamd nginx kresd@1 fail2ban; do
        systemctl is-active --quiet "$unit" || problem "service $unit is not running"
      done
      failed=$(systemctl list-units --failed --plain --no-legend | awk '{print $1}' | tr '\n' ' ')
      [[ -z "$failed" ]] || problem "failed systemd units: $failed"

      # 2. TLS certificate (Postfix/Dovecot); MTA-STS makes an expired one fatal
      cert=/var/lib/acme/${ctx.fqdn}/cert.pem
      if [[ ! -f $cert ]]; then
        problem "no TLS certificate at $cert"
      elif ! openssl x509 -checkend $((14 * 86400)) -noout -in "$cert" > /dev/null; then
        problem "TLS certificate expires within 14 days: $(openssl x509 -enddate -noout -in "$cert")"
      elif openssl x509 -noout -issuer -in "$cert" | grep -qi minica; then
        problem "TLS certificate is the self-signed placeholder: Let's Encrypt issuance failed"
      fi

      # 3. Disk
      used=$(df --output=pcent / | tail -n1 | tr -dc 0-9)
      (( used < ${toString cfg.diskWarnPercent} )) || problem "disk / is $used% full"

      # 4. Mail queue
      queued=$(postqueue -j 2> /dev/null | wc -l)
      (( queued < ${toString cfg.queueWarn} )) || problem "$queued messages in the mail queue"

      # 5. Outbound SMTP (blocked by the provider, or by OVH's anti-spam)
      if ! timeout 10 bash -c 'exec 3<>/dev/tcp/gmail-smtp-in.l.google.com/25' 2> /dev/null; then
        problem "cannot connect to gmail-smtp-in.l.google.com:25: outbound SMTP blocked?"
      fi

      # 6. Blocklists, for the public IPv4 address (queried through the local
      #    resolver; 127.255.255.x means the list refused the query)
      ip=$(curl -4 -fsS -m 10 https://api.ipify.org || true)
      if [[ $ip =~ ^[0-9.]+$ ]]; then
        rev=$(awk -F. '{print $4"."$3"."$2"."$1}' <<< "$ip")
        for bl in zen.spamhaus.org bl.spamcop.net; do
          answer=$(dig +short "$rev.$bl" A @127.0.0.1 | head -n1)
          if [[ -n $answer && $answer != 127.255.255.* ]]; then
            problem "$ip is listed on $bl ($answer)"
          fi
        done
      fi

      # Report
      if (( ''${#problems[@]} == 0 )); then
        report="OK"
      else
        report=$(printf '%s\n' "''${problems[@]}")
      fi
      echo "$report"
      ${
        if cfg.healthcheckUrl != "" then
          ''
            if (( ''${#problems[@]} == 0 )); then
              curl -fsS -m 10 --retry 3 --data-raw "$report" "${cfg.healthcheckUrl}" > /dev/null
            else
              curl -fsS -m 10 --retry 3 --data-raw "$report" "${cfg.healthcheckUrl}/fail" > /dev/null
            fi
          ''
        else
          ''
            if (( ''${#problems[@]} > 0 )) \
               && ! [[ $(find ${stateDir}/last-mail -mmin -1440 2> /dev/null) ]]; then
              /run/wrappers/bin/sendmail -t <<MAIL
            From: root@${ctx.fqdn}
            To: ${settings.adminEmail}
            Subject: Mail server ${ctx.fqdn}: ''${#problems[@]} problem(s)

            $report
            MAIL
              touch ${stateDir}/last-mail
            fi
          ''
      }
    '';
  };

  systemd.timers.mail-health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };

  assertions = [
    {
      assertion = cfg.healthcheckUrl == "" || lib.hasPrefix "https://" cfg.healthcheckUrl;
      message = "settings.nix: monitoring.healthcheckUrl must be an https:// URL.";
    }
  ];
}
