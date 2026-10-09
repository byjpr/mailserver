#!/usr/bin/env bash
# Store the SMTP relay password (settings.relay) in secrets/secrets.yaml.
source "$(dirname "$0")/lib.sh"
require_secrets

read -rsp "Relay SMTP password / API key: " password; echo
[[ -n "$password" ]] || die "empty password"
sops_set '["relay"]["password"]' "$password"
info "Stored. Set relay.enable = true in settings.nix and run 'just deploy'."
