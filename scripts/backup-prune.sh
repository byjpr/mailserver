#!/usr/bin/env bash
# Delete old backup snapshots according to settings.backup.keep, running
# restic on this machine. Needed when backup.appendOnly is set (the server is
# then not allowed to delete anything); use credentials that may delete,
# e.g. a separate bucket key exported in AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY.
source "$(dirname "$0")/lib.sh"
require_secrets

backup="$(setting backup)"
export RESTIC_REPOSITORY RESTIC_PASSWORD
RESTIC_REPOSITORY="$(jq -r .repository <<< "$backup")"
RESTIC_PASSWORD="$(sops decrypt --extract '["backup"]["password"]' "$SECRETS")"
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  echo "Using the server's bucket credentials (set AWS_ACCESS_KEY_ID and"
  echo "AWS_SECRET_ACCESS_KEY to use a key that is allowed to delete)."
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  AWS_ACCESS_KEY_ID="$(sops decrypt --extract '["backup"]["s3_access_key_id"]' "$SECRETS")"
  AWS_SECRET_ACCESS_KEY="$(sops decrypt --extract '["backup"]["s3_secret_access_key"]' "$SECRETS")"
fi

restic forget --prune \
  --keep-daily "$(jq -r .keep.daily <<< "$backup")" \
  --keep-weekly "$(jq -r .keep.weekly <<< "$backup")" \
  --keep-monthly "$(jq -r .keep.monthly <<< "$backup")"
