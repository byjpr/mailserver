#!/usr/bin/env bash
# Install NixOS onto the server created by `just apply`, wiping its disk.
#
# The server runs the provider's stock Debian/Ubuntu image. First the disk
# and network facts NixOS needs are recorded in machine.json; then
# nixos-anywhere kexecs into a NixOS installer, partitions the disk with
# disko and installs this flake. The pre-generated SSH host key is copied in
# so the server can decrypt its secrets on first boot and its fingerprint
# matches known_hosts.
source "$(dirname "$0")/lib.sh"
require_secrets
cd "$ROOT"

ip="$(tofu_server output -raw ipv4)"
[[ -n "$ip" ]] || die "no server IP in Terraform state; run 'just apply' first"
name="$(fqdn)"
user="$(tfvars | jq -r .providerInfo.installUser)"

cat <<EOF2
This will ERASE the disk of $ip ($name) and install NixOS.
Make sure DNS for $name already resolves to $ip, or the TLS certificates
cannot be issued on first boot.
EOF2
read -rp "Type the host name to continue: " confirm
[[ "$confirm" == "$name" ]] || die "aborted"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Network facts the provider's API knows better than the stock image
# (netcup: the IPv6 /64 is not configured in its images).
tf_network=""
if tofu_server output -json network > "$tmp/network.json" 2> /dev/null; then
  tf_network="$tmp/network.json"
fi
"$ROOT/scripts/detect-machine.sh" "$user@$ip" "$tf_network"

install -d -m 755 "$tmp/root/etc/ssh"
(umask 077 && sops decrypt --input-type binary --output-type binary "$HOST_KEY_ENC" > "$tmp/root/etc/ssh/ssh_host_ed25519_key")
cp "$HOST_KEY_PUB" "$tmp/root/etc/ssh/ssh_host_ed25519_key.pub"

build_args=()
if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  build_args=(--build-on remote)
fi

# Boot an installer built from our own pinned nixpkgs (flake.lock), rather
# than nixos-anywhere's default: the latest image from a GitHub release.
if kexec="$(nix build --no-link --print-out-paths "$ROOT#kexec-installer" 2> /dev/null)"; then
  build_args+=(--kexec "$kexec/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz")
else
  echo "warning: cannot build the x86_64-linux installer image on this machine (no" >&2
  echo "Linux builder); falling back to nixos-anywhere's download from GitHub." >&2
fi

nixos-anywhere \
  --flake "$ROOT#mail" \
  --extra-files "$tmp/root" \
  ${build_args[@]+"${build_args[@]}"} \
  --target-host "$user@$ip"

# Pin the host key for all future connections.
echo "$name,$ip $(cut -d' ' -f1,2 "$HOST_KEY_PUB")" > "$KNOWN_HOSTS"
git add "$KNOWN_HOSTS" machine.json
info "Installed. Commit machine.json and known_hosts, then run 'just check'."
