# The NixOS release this flake follows, and when it stops receiving security
# updates. Both nixpkgs and simple-nixos-mailserver in flake.nix must point
# at this release (a flake check enforces the nixpkgs half).
#
# Upgrade before the end-of-life date: see docs/upgrading.md.
{
  release = "26.05";
  # NixOS releases are supported for one month after the next release.
  endOfLife = "2026-12-31";
  # Warn this many days before end of life (on the server and in CI).
  warnDays = 30;
}
