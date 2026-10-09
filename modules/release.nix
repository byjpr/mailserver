# Warn the admin by mail, weekly, once the NixOS release this server runs is
# close to (or past) its end of life, after which it gets no security updates.
{
  lib,
  pkgs,
  settings,
  ...
}:
let
  r = import ../lib/release.nix;
in
{
  assertions = [
    {
      assertion = lib.trivial.release == r.release;
      message = "lib/release.nix says NixOS ${r.release}, but nixpkgs is ${lib.trivial.release}. Update lib/release.nix (see docs/upgrading.md).";
    }
  ];

  systemd.services.release-support-check = {
    description = "Warn when NixOS ${r.release} is close to end of life";
    path = [ pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      eol=$(date -d ${r.endOfLife} +%s)
      now=$(date +%s)
      days=$(( (eol - now) / 86400 ))
      (( days <= ${toString r.warnDays} )) || exit 0
      if (( days < 0 )); then
        subject="NixOS ${r.release} on $(hostname -f) is END OF LIFE: no more security updates"
      else
        subject="NixOS ${r.release} on $(hostname -f) reaches end of life in $days days"
      fi
      echo "$subject" >&2
      /run/wrappers/bin/sendmail -t <<MAIL
      From: root@$(hostname -f)
      To: ${settings.adminEmail}
      Subject: $subject

      This mail server runs NixOS ${r.release}, which stops receiving security
      updates on ${r.endOfLife}. Upgrade to the next release as described in
      docs/upgrading.md of the configuration repository, then run
      'just deploy'.
      MAIL
    '';
  };
  systemd.timers.release-support-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "6h";
    };
  };
}
