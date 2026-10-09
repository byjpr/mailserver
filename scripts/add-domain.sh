#!/usr/bin/env bash
# Generate a DKIM key pair for a domain.
#
#   add-domain.sh <domain> [selector]
#
# The private key goes into secrets/secrets.yaml (encrypted); the public key
# goes to dkim/<domain>/<selector>.txt, from which both the server config and
# the DNS records are generated. The default selector is date-based
# (e.g. s202610), which makes key rotation simple: run this again with a new
# selector, deploy, wait a few days for DNS caches, then delete the old one.
source "$(dirname "$0")/lib.sh"
require_secrets

domain="${1:?usage: add-domain.sh <domain> [selector]}"
selector="${2:-s$(date +%Y%m)}"
[[ "$selector" =~ ^[a-z0-9-]+$ ]] || die "selector must be lowercase letters, digits and dashes"

pub_file="$ROOT/dkim/$domain/$selector.txt"
[[ ! -f "$pub_file" ]] || die "$pub_file already exists"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

info "Generating 2048-bit RSA DKIM key for $domain (selector $selector)"
(umask 077 && openssl genrsa -out "$tmp/key.pem" 2048 2>/dev/null)
pub="$(openssl rsa -in "$tmp/key.pem" -pubout -outform DER 2>/dev/null | openssl base64 -A)"

sops_set "[\"dkim\"][\"$domain\"][\"$selector\"]" "$(cat "$tmp/key.pem")"
mkdir -p "$(dirname "$pub_file")"
echo "v=DKIM1; k=rsa; p=$pub" > "$pub_file"

info "Wrote $pub_file"
if ! setting domains | jq -e --arg d "$domain" 'index($d)' > /dev/null; then
  echo "    Remember to add \"$domain\" to 'domains' in settings.nix, and a"
  echo "    postmaster@$domain address to one of your accounts."
fi
