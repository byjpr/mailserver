#!/usr/bin/env bash
# Print every DNS record the setup needs, in zone-file notation. Use this when
# DNS is not managed by Terraform (settings.dns = "manual").
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

ip4="$(tofu_server output -raw ipv4 2>/dev/null || echo '<server IPv4>')"
ip6="$(tofu_server output -raw ipv6 2>/dev/null || echo '<server IPv6>')"
name="$(fqdn)"

echo "; Mail host"
echo "$name. 3600 IN A    $ip4"
[[ -z "$ip6" ]] || echo "$name. 3600 IN AAAA $ip6"
echo "; Reverse DNS (PTR) for each address must be $name. ('just apply' sets it"
echo "; where the provider allows; see docs/providers.md)"
echo "; TXT values over 255 characters (DKIM) may need splitting into quoted"
echo "; 255-character strings, depending on your DNS host."
echo
nix eval --json "$ROOT#tfvars.dnsRecords" | jq -r '
  .[] |
  (if .name == "@" then .domain else "\(.name).\(.domain)" end) as $fqdn |
  if .type == "MX" then "\($fqdn). 3600 IN MX \(.priority) \(.value)"
  elif .type == "SRV" then "\($fqdn). 3600 IN SRV \(.priority) \(.weight) \(.port) \(.value)"
  elif .type == "CAA" then "\($fqdn). 3600 IN CAA \(.flags) \(.tag) \"\(.value)\""
  elif .type == "TXT" then "\($fqdn). 3600 IN TXT \"\(.value)\""
  else "\($fqdn). 3600 IN \(.type) \(.value)" end'
