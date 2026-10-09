#!/usr/bin/env bash
# Record the facts NixOS needs about a freshly provisioned server, while it
# still runs the provider's stock Linux image, in machine.json:
#   - the disk the root filesystem is on (disko wipes and partitions it)
#   - the MAC address, addresses and gateways of the public interface, for
#     providers that don't hand them out via DHCP/router advertisements
#
#   detect-machine.sh <user@ip> [terraform-network.json]
#
# If the provider's Terraform step knows the network configuration (netcup),
# pass it as the second argument; its addresses take precedence.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

target="${1:?usage: detect-machine.sh <user@ip> [network.json]}"
tf_network="${2:-}"
out="$ROOT/machine.json"

info "Reading disk and network configuration of $target"
# The stock image's host key is unknown and is thrown away with the image, so
# it is accepted once into a throw-away known_hosts file.
tmp_known="$(mktemp)"
trap 'rm -f "$tmp_known"' EXIT
raw="$(ssh -o UserKnownHostsFile="$tmp_known" -o StrictHostKeyChecking=accept-new "$target" '
  root_dev="$(findmnt -no SOURCE /)"
  disk="/dev/$(lsblk -no PKNAME "$root_dev" | head -n1)"
  printf "{\"disk\":\"%s\",\"links\":%s,\"a4\":%s,\"r4\":%s,\"a6\":%s,\"r6\":%s}" "$disk" \
    "$(ip -j link show)" \
    "$(ip -j -4 addr show scope global)" "$(ip -j -4 route show default)" \
    "$(ip -j -6 addr show scope global)" "$(ip -j -6 route show default)"
')"

echo "$raw" | jq '
  def iface(a; family):
    [a[] | {ifname, info: (.addr_info[]? | select(.family == family
                  and (.temporary | not) and (.deprecated | not)))}] | first;
  def gw(r): [r[] | select(.gateway != null) | .gateway] | first;
  . as $all
  | iface(.a4; "inet") as $v4
  | iface(.a6; "inet6") as $v6
  | {
      disk: .disk,
      mac: (if $v4 then [$all.links[] | select(.ifname == $v4.ifname) | .address] | first else null end),
      ipv4: (if $v4 and gw(.r4) then
               {address: $v4.info.local, prefixLength: $v4.info.prefixlen, gateway: gw(.r4)}
             else null end),
      ipv6: (if $v6 and gw(.r6) then
               {address: $v6.info.local, prefixLength: $v6.info.prefixlen, gateway: gw(.r6)}
             else null end)
    }' > "$out.tmp"

if [[ -n "$tf_network" ]]; then
  jq -s '.[0] * .[1]' "$out.tmp" "$tf_network" > "$out"
  rm "$out.tmp"
else
  mv "$out.tmp" "$out"
fi

cat "$out"
[[ "$(jq -r .disk "$out")" == /dev/?* ]] || die "could not determine the root disk"
jq -e '.ipv4' "$out" > /dev/null || die "no global IPv4 address/default route found"
# Flakes only see files tracked by git.
git add "$out"
info "Wrote machine.json (staged in git). Commit it after the install."
