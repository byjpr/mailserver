#!/usr/bin/env bash
# Record the public network configuration of a freshly provisioned server
# (still running the provider's stock Linux image) in network.json, for
# providers whose addresses are not handed out by DHCP/router advertisements.
# The NixOS configuration reads network.json and configures the same
# addresses statically.
#
#   detect-network.sh <ip>
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

ip="${1:?usage: detect-network.sh <ip>}"
out="$ROOT/network.json"

info "Reading the network configuration of $ip"
# The stock image's host key is unknown and is thrown away with the image, so
# it is accepted once into a throw-away known_hosts file.
tmp_known="$(mktemp)"
trap 'rm -f "$tmp_known"' EXIT
raw="$(ssh -o UserKnownHostsFile="$tmp_known" -o StrictHostKeyChecking=accept-new "root@$ip" '
  printf "{\"a4\":%s,\"r4\":%s,\"a6\":%s,\"r6\":%s}" \
    "$(ip -j -4 addr show scope global)" "$(ip -j -4 route show default)" \
    "$(ip -j -6 addr show scope global)" "$(ip -j -6 route show default)"
')"

echo "$raw" | jq '
  def addr(a; family):
    [a[] | .addr_info[]? | select(.family == family and (.temporary | not) and (.deprecated | not))]
    | first;
  def gw(r): [r[] | select(.gateway != null) | .gateway] | first;
  {
    ipv4: (addr(.a4; "inet") as $a | gw(.r4) as $g
           | if $a and $g then {address: $a.local, prefixLength: $a.prefixlen, gateway: $g} else null end),
    ipv6: (addr(.a6; "inet6") as $a | gw(.r6) as $g
           | if $a and $g then {address: $a.local, prefixLength: $a.prefixlen, gateway: $g} else null end)
  }' > "$out"

cat "$out"
jq -e '.ipv4' "$out" > /dev/null || die "no global IPv4 address/default route found on $ip"
jq -e --arg ip "$ip" '.ipv4.address == $ip' "$out" > /dev/null \
  || echo "warning: detected IPv4 $(jq -r .ipv4.address "$out") differs from $ip" >&2
# Flakes only see files tracked by git.
git add "$out"
info "Wrote network.json (staged in git). Commit it together with the install."
