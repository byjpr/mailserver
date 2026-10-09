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

# Terraform state is committed to git, encrypted with OpenTofu's state
# encryption. The passphrase lives in secrets/secrets.yaml, so anyone who can
# decrypt the secrets can work on the infrastructure from any machine.
use_state_encryption() {
  [[ -z "${TF_ENCRYPTION:-}" ]] || return 0
  require_secrets
  local passphrase
  if ! passphrase="$(sops decrypt --extract '["terraform"]["state_passphrase"]' "$SECRETS" 2> /dev/null)"; then
    info "Creating the Terraform state passphrase in secrets/secrets.yaml"
    passphrase="$(openssl rand -base64 33)"
    sops_set '["terraform"]["state_passphrase"]' "$passphrase"
  fi
  TF_ENCRYPTION="$(cat <<TFENC
key_provider "pbkdf2" "main" {
  passphrase = "$passphrase"
}
method "aes_gcm" "main" {
  keys = key_provider.pbkdf2.main
}
state {
  method   = method.aes_gcm.main
  enforced = true
}
plan {
  method   = method.aes_gcm.main
  enforced = true
}
TFENC
)"
  export TF_ENCRYPTION
}

# tofu in the selected provider's server step.
tofu_server() {
  use_state_encryption
  tofu -chdir="$(server_dir)" "$@"
}

# Refuse to touch infrastructure when the server was installed (known_hosts
# exists) but the Terraform state for it is missing: applying would create a
# second, empty server and point DNS at it.
require_server_state() {
  [[ -f "$KNOWN_HOSTS" ]] || return 0
  if [[ -z "$(tofu_server state list 2> /dev/null)" ]]; then
    die "known_hosts says a server is installed, but $(server_dir)/terraform.tfstate has no
resources. Applying now would create a second server and move DNS to it.
Restore the state from git (git log -- '$(server_dir)/terraform.tfstate'),
or import the existing server, before running this again."
  fi
}

ssh_opts() {
  echo "-o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes"
}
