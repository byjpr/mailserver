# Fixed settings used by the `example` CI check (see flake.nix). They exercise
# the optional features (second domain, forwarding/SRS, relay) with dummy
# values; tests/dkim holds throw-away public keys whose private halves were
# discarded. This configuration is never deployed.
import ../settings.nix
// {
  domains = [
    "example.com"
    "example.org"
  ];
  accounts = {
    "admin@example.com" = {
      aliases = [
        "postmaster@example.com"
        "abuse@example.com"
        "dmarc-reports@example.com"
        "tls-reports@example.com"
        "postmaster@example.org"
        "abuse@example.org"
      ];
      quota = "5G";
    };
    "app@example.org" = {
      sendOnly = true;
    };
  };
  forwards = {
    "someone@example.org" = "someone@elsewhere.test";
  };
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl ci@example"
  ];
  sshAllowedCidrs = [
    "198.51.100.0/24"
    "2001:db8:1::/48"
  ];
  relay = {
    enable = true;
    host = "smtp.relay.test";
    port = 587;
    username = "ci";
    spfInclude = "spf.relay.test";
  };
  backup = {
    enable = true;
    repository = "s3:https://s3.example.test/bucket/mail";
    schedule = "daily";
    keep = {
      daily = 7;
      weekly = 5;
      monthly = 12;
    };
    appendOnly = false;
  };
  autoUpgrade = {
    enable = true;
    flake = "github:example/mailserver";
  };
}
