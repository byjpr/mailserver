#!/usr/bin/env bash
# Switch nixpkgs and simple-nixos-mailserver to a new NixOS release branch.
#
#   upgrade-release.sh <release> <end-of-life YYYY-MM-DD>
#
# Then read the release notes (docs/upgrading.md), build and deploy.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

new="${1:?usage: upgrade-release.sh <release, e.g. 26.11> <end of life, e.g. 2027-06-30>}"
eol="${2:?usage: upgrade-release.sh <release> <end of life>}"
[[ "$new" =~ ^[0-9]{2}\.(05|11)$ ]] || die "release must look like 26.11"
[[ "$eol" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "end of life must be YYYY-MM-DD"

old="$(nix eval --raw --file lib/release.nix release)"
[[ "$old" != "$new" ]] || die "already on $new"

info "Switching flake inputs from nixos-$old to nixos-$new"
sed -i.bak "s/nixos-$old/nixos-$new/g" flake.nix && rm flake.nix.bak
sed -i.bak -e "s/release = \"$old\";/release = \"$new\";/" \
  -e "s/endOfLife = \"[0-9-]*\";/endOfLife = \"$eol\";/" lib/release.nix && rm lib/release.nix.bak
nix flake update

cat <<EOF2

Done. Before deploying:
  1. Read the release notes for NixOS $new and simple-nixos-mailserver $new
     (https://nixos-mailserver.readthedocs.io/en/latest/release-notes.html):
     the mail module may ask you to raise mailserver.stateVersion and run a
     migration.
  2. If system.stateVersion-related warnings appear, do NOT change
     system.stateVersion in modules/hardening.nix.
  3. just build && just deploy, then just check.
EOF2
