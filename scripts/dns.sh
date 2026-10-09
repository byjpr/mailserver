#!/usr/bin/env bash
# Print every DNS record the setup needs, in zone-file notation. Use this when
# DNS is hosted somewhere other than DigitalOcean (settings.manageDns = false).
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

ip4="$(tofu -chdir=terraform output -raw ipv4 2>/dev/null || echo '<droplet IPv4>')"
ip6="$(tofu -chdir=terraform output -raw ipv6 2>/dev/null || echo '<droplet IPv6>')"
name="$(fqdn)"

echo "; Mail host"
echo "$name. 3600 IN A    $ip4"
echo "$name. 3600 IN AAAA $ip6"
echo "; Reverse DNS (PTR) for both addresses must be $name. — DigitalOcean sets"
echo "; this automatically because the droplet is named $name."
echo
nix eval --json "$ROOT#tfvars.dnsRecords" | jq -r '
  .[] |
  (if .name == "@" then .domain else "\(.name).\(.domain)" end) as $fqdn |
  if .type == "MX" then "\($fqdn). 3600 IN MX \(.priority) \(.value)"
  elif .type == "SRV" then "\($fqdn). 3600 IN SRV \(.priority) \(.weight) \(.port) \(.value)"
  elif .type == "CAA" then "\($fqdn). 3600 IN CAA \(.flags) \(.tag) \"\(.value | rtrimstr("."))\""
  elif .type == "TXT" then "\($fqdn). 3600 IN TXT \"\(.value)\""
  else "\($fqdn). 3600 IN \(.type) \(.value)" end'
