#!/usr/bin/env bash
# Store the backup bucket credentials in secrets/secrets.yaml and generate the
# restic repository password (settings.backup).
source "$(dirname "$0")/lib.sh"
require_secrets

repo="$(setting backup.repository | jq -r .)"
[[ -n "$repo" ]] || die "set backup.repository in settings.nix first"
info "Repository: $repo"

read -rp "Bucket access key ID: " key_id
read -rsp "Bucket secret access key: " secret; echo
[[ -n "$key_id" && -n "$secret" ]] || die "both values are required"
sops_set '["backup"]["s3_access_key_id"]' "$key_id"
sops_set '["backup"]["s3_secret_access_key"]' "$secret"

if sops decrypt --extract '["backup"]["password"]' "$SECRETS" > /dev/null 2>&1; then
  info "Keeping the existing restic password."
else
  password="$(openssl rand -base64 32)"
  sops_set '["backup"]["password"]' "$password"
  cat <<EOF2

Generated restic repository password:

    $password

Store it in your password manager NOW. The backups can only be restored
with it, and it must not depend on this repository or the server surviving.
EOF2
fi
echo
echo "Next: set backup.enable = true in settings.nix, then just deploy && just backup-now"
