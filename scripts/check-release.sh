#!/usr/bin/env bash
# Fail (exit 1) if the NixOS release in lib/release.nix is within warnDays of
# its end of life, or past it. Used by CI; also handy locally.
source "$(dirname "$0")/lib.sh"

r="$(nix eval --json --file "$ROOT/lib/release.nix")"
release="$(jq -r .release <<< "$r")"
eol="$(jq -r .endOfLife <<< "$r")"
warn="$(jq -r .warnDays <<< "$r")"
# GNU date (Linux) or BSD date (macOS).
eol_s="$(date -d "$eol" +%s 2>/dev/null || date -j -f %Y-%m-%d "$eol" +%s)"
days=$(( (eol_s - $(date +%s)) / 86400 ))

if (( days < 0 )); then
  echo "NixOS $release has been END OF LIFE since $eol: no security updates. See docs/upgrading.md." >&2
  exit 1
elif (( days <= warn )); then
  echo "NixOS $release reaches end of life in $days days ($eol). See docs/upgrading.md." >&2
  exit 1
fi
echo "NixOS $release is supported until $eol ($days days)."
