# Encrypted, off-site backups of all mail with restic, to any S3-compatible
# bucket (Backblaze B2, OVHcloud Object Storage, Wasabi, AWS S3, ...).
#
# Secrets (`just backup-setup`): the restic repository password and the
# bucket credentials, stored in secrets/secrets.yaml. Keep a copy of the
# restic password somewhere else too: without it the backups are useless.
{
  config,
  lib,
  settings,
  ...
}:
let
  cfg = settings.backup;
in
lib.mkIf cfg.enable {
  sops.secrets."backup/password" = { };
  sops.secrets."backup/s3_access_key_id" = { };
  sops.secrets."backup/s3_secret_access_key" = { };
  sops.templates."restic-environment".content = ''
    AWS_ACCESS_KEY_ID=${config.sops.placeholder."backup/s3_access_key_id"}
    AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."backup/s3_secret_access_key"}
  '';

  services.restic.backups.mail = {
    inherit (cfg) repository;
    initialize = true;
    passwordFile = config.sops.secrets."backup/password".path;
    environmentFile = config.sops.templates."restic-environment".path;
    paths = [
      config.mailserver.storage.path # all mailboxes, including Sieve scripts
      "/var/lib/redis-rspamd" # Rspamd's learned spam/ham data
    ];
    timerConfig = {
      OnCalendar = cfg.schedule;
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
    # With an append-only/object-lock bucket the server cannot delete old
    # snapshots (that is the point); prune from your own machine instead
    # with `just backup-prune`.
    pruneOpts = lib.optionals (!cfg.appendOnly) [
      "--keep-daily ${toString cfg.keep.daily}"
      "--keep-weekly ${toString cfg.keep.weekly}"
      "--keep-monthly ${toString cfg.keep.monthly}"
    ];
    runCheck = true;
    checkOpts = [ "--read-data-subset=1%" ];
  };

  assertions = [
    {
      assertion = cfg.repository != "";
      message = "settings.nix: backup.enable is set but backup.repository is empty.";
    }
  ];
}
