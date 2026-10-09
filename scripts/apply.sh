#!/usr/bin/env bash
# Create or update the infrastructure, in order:
#   1. the server (infra/servers/<provider>)
#   2. the DNS records (infra/dns/<dns>), using the server's addresses
#   3. reverse DNS, for providers that only accept it once the forward
#      records resolve (OVHcloud)
#
#   apply.sh [plan]
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

mode="${1:-apply}"
vars="$(tfvars)"

# Provider credentials kept in the encrypted secrets instead of the shell
# environment (currently: the netcup token from `just netcup-login`).
if [[ "$(provider)" == netcup && -z "${NETCUP_SCP_REFRESH_TOKEN:-}" ]]; then
  require_secrets
  NETCUP_SCP_REFRESH_TOKEN="$(sops decrypt --extract '["netcup"]["scp_refresh_token"]' "$SECRETS" 2> /dev/null)" \
    || die "no netcup token: run 'just netcup-login' first"
  export NETCUP_SCP_REFRESH_TOKEN
fi
info "Provider: $(provider), DNS: $(jq -r .dns <<< "$vars")"

server="$(server_dir)"
jq '{mail: .}' <<< "$vars" > "$server/settings.auto.tfvars.json"
tofu -chdir="$server" init -input=false > /dev/null

if [[ "$mode" == plan ]]; then
  tofu -chdir="$server" plan
  echo "(DNS changes are planned once the server exists: run 'just apply'.)"
  exit 0
fi

info "1/3 Server"
tofu -chdir="$server" apply
ipv4="$(tofu -chdir="$server" output -raw ipv4)"
ipv6="$(tofu -chdir="$server" output -raw ipv6)"
info "Server addresses: $ipv4 ${ipv6:-(no IPv6)}"

info "2/3 DNS records"
case "$(jq -r .dns <<< "$vars")" in
  cloudflare)
    dns="$ROOT/infra/dns/cloudflare"
    jq '{mail: .}' <<< "$vars" > "$dns/settings.auto.tfvars.json"
    jq -n --arg v4 "$ipv4" --arg v6 "$ipv6" '{server: {ipv4: $v4, ipv6: $v6}}' \
      > "$dns/server.auto.tfvars.json"
    tofu -chdir="$dns" init -input=false > /dev/null
    tofu -chdir="$dns" apply
    ;;
  manual)
    echo "Create these records with your DNS provider (also: just dns):"
    "$ROOT/scripts/dns.sh"
    read -rp "Press enter once they are published... "
    ;;
  *) die "unknown dns setting" ;;
esac

if jq -e .providerInfo.reverseDnsNeedsForwardDns <<< "$vars" > /dev/null; then
  info "3/3 Reverse DNS (waiting for $(fqdn) to resolve to $ipv4)"
  for _ in $(seq 60); do
    [[ "$(dig +short A "$(fqdn)" @1.1.1.1 | tail -n1)" == "$ipv4" ]] && break
    sleep 10
  done
  tofu -chdir="$server" apply -var dns_ready=true
else
  info "3/3 Reverse DNS was handled in step 1"
fi

note="$(jq -r .providerInfo.afterApply <<< "$vars")"
if [[ -n "$note" ]]; then
  echo
  echo "ACTION NEEDED: $note" | sed -e "s/{ipv4}/$ipv4/g" -e "s/{fqdn}/$(fqdn)/g"
fi
echo
echo "Next: just install"
