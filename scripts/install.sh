#!/usr/bin/env bash
# Install NixOS onto the droplet created by Terraform, wiping its disk.
#
# The droplet boots a stock Ubuntu image; nixos-anywhere kexecs into a NixOS
# installer, partitions the disk with disko and installs this flake. The
# pre-generated SSH host key is copied in so the server can decrypt its
# secrets on first boot and its fingerprint matches known_hosts.
source "$(dirname "$0")/lib.sh"
require_secrets
cd "$ROOT"

ip="$(tofu -chdir=terraform output -raw ipv4)"
[[ -n "$ip" ]] || die "no droplet IP in Terraform state; run 'just apply' first"
name="$(fqdn)"

cat <<EOF
This will ERASE the disk of $ip ($name) and install NixOS.
Make sure DNS for $name already resolves to $ip, or the TLS certificates
cannot be issued on first boot.
EOF
read -rp "Type the host name to continue: " confirm
[[ "$confirm" == "$name" ]] || die "aborted"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
install -d -m 755 "$tmp/etc/ssh"
(umask 077 && sops decrypt --input-type binary --output-type binary "$HOST_KEY_ENC" > "$tmp/etc/ssh/ssh_host_ed25519_key")
cp "$HOST_KEY_PUB" "$tmp/etc/ssh/ssh_host_ed25519_key.pub"

build_args=()
if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  build_args=(--build-on remote)
fi

nixos-anywhere \
  --flake "$ROOT#mail" \
  --extra-files "$tmp" \
  ${build_args[@]+"${build_args[@]}"} \
  --target-host "root@$ip"

# Pin the host key for all future connections.
echo "$name,$ip $(cut -d' ' -f1,2 "$HOST_KEY_PUB")" > "$KNOWN_HOSTS"
info "Installed. Host key pinned in known_hosts. Check the setup with 'just check'."
