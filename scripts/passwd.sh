#!/usr/bin/env bash
# Set the password of a mailbox.
#
#   passwd.sh <address>            prompt for a password
#   passwd.sh <address> --random   generate one and print it once
#
# Only a yescrypt hash is stored (encrypted) in secrets/secrets.yaml.
source "$(dirname "$0")/lib.sh"
require_secrets

address="${1:?usage: passwd.sh <address> [--random]}"
setting accounts | jq -e --arg a "$address" 'has($a)' > /dev/null \
  || echo "warning: $address is not (yet) listed under 'accounts' in settings.nix" >&2

if [[ "${2:-}" == "--random" ]]; then
  password="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"
  echo "Generated password for $address: $password"
else
  read -rsp "New password for $address: " password; echo
  read -rsp "Repeat: " again; echo
  [[ "$password" == "$again" ]] || die "passwords do not match"
  (( ${#password} >= 12 )) || die "use at least 12 characters"
fi

hash="$(printf '%s' "$password" | mkpasswd -m yescrypt -s 2>/dev/null \
  || printf '%s' "$password" | mkpasswd -m sha-512 -R 500000 -s)"
[[ "$hash" == \$* ]] || die "mkpasswd failed"

sops_set "[\"mailboxes\"][\"$address\"]" "$hash"
info "Stored hash for $address. Run 'just deploy' to apply it."
