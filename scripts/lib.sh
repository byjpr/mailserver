# shellcheck shell=bash disable=SC2034,SC2016
# Shared helpers for the scripts in this directory. Source, don't execute.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS="$ROOT/secrets/secrets.yaml"
HOST_KEY_ENC="$ROOT/secrets/ssh_host_ed25519_key.enc"
HOST_KEY_PUB="$ROOT/secrets/ssh_host_ed25519_key.pub"
KNOWN_HOSTS="$ROOT/known_hosts"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }

# Where sops looks for the admin's age identity.
age_key_file() {
  if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
    echo "$SOPS_AGE_KEY_FILE"
  elif [[ "$(uname)" == "Darwin" ]]; then
    echo "$HOME/Library/Application Support/sops/age/keys.txt"
  else
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt"
  fi
}

# Evaluate an attribute of settings.nix as JSON.
setting() {
  nix eval --json --file "$ROOT/settings.nix" "$1"
}

fqdn() {
  nix eval --raw --file "$ROOT/settings.nix" --apply 's: "${s.hostname}.${s.primaryDomain}"'
}

require_secrets() {
  [[ -f "$SECRETS" ]] || die "secrets/secrets.yaml not found; run 'just init' first."
}

# sops set wants the value as a JSON literal.
sops_set() {
  local path="$1" value="$2"
  sops set "$SECRETS" "$path" "$(jq -Rn --arg v "$value" '$v')"
}

# The flake's Terraform variables (settings.nix + DKIM keys) as JSON.
tfvars() {
  nix eval --json "$ROOT#tfvars"
}

provider() {
  setting provider | jq -r .
}

server_dir() {
  echo "$ROOT/infra/servers/$(provider)"
}

# tofu in the selected provider's server step.
tofu_server() {
  tofu -chdir="$(server_dir)" "$@"
}

ssh_opts() {
  echo "-o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes"
}
