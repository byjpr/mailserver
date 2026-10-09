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

# Verify the stock image's SSH host key before sending it anything: the
# install uploads the server's private host key, which also decrypts every
# secret. Without verification, whoever intercepts this connection gets it.
pin="$tmp/known_hosts"
ssh-keyscan -t ed25519 -T 15 "$ip" 2> /dev/null > "$pin" || true
[[ -s "$pin" ]] || die "could not read an ed25519 host key from $ip (is the server up?)"
fingerprint="$(ssh-keygen -lf "$pin" | awk '{print $2}')"
cat <<EOF2

The server at $ip presents this SSH host key:

    $fingerprint (ED25519)

Compare it with the one the server itself reports, in the provider's web
console: cloud-init prints "SSH HOST KEY FINGERPRINTS" in the boot log, or log
in there and run: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
EOF2
if [[ -n "${INSTALL_HOST_FINGERPRINT:-}" ]]; then
  [[ "$INSTALL_HOST_FINGERPRINT" == "$fingerprint" ]] \
    || die "fingerprint mismatch: expected $INSTALL_HOST_FINGERPRINT"
else
  read -rp "Paste the fingerprint from the console (or type 'trust' to skip): " answer
  if [[ "$answer" == trust ]]; then
    echo "warning: continuing without verifying the host key" >&2
  elif [[ "$answer" != "$fingerprint" ]]; then
    die "fingerprint mismatch; not installing"
  fi
fi

# nixos-anywhere passes "-o StrictHostKeyChecking=no" itself, and OpenSSH
# uses the first value given for an option, so put the pinned settings in
# front of every ssh call it makes. The kexec installer keeps the stock
# image's host keys, so the pin also holds after kexec.
real_ssh="$(command -v ssh)"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/ssh" <<EOF2
#!/usr/bin/env bash
exec "$real_ssh" -o UserKnownHostsFile="$pin" -o StrictHostKeyChecking=yes "\$@"
EOF2
chmod +x "$tmp/bin/ssh"

# Network facts the provider's API knows better than the stock image
# (netcup: the IPv6 /64 is not configured in its images).
tf_network=""
if tofu_server output -json network > "$tmp/network.json" 2> /dev/null; then
  tf_network="$tmp/network.json"
fi
"$ROOT/scripts/detect-machine.sh" "$user@$ip" "$pin" "$tf_network"

install -d -m 755 "$tmp/root/etc/ssh"
(umask 077 && sops decrypt --input-type binary --output-type binary "$HOST_KEY_ENC" > "$tmp/root/etc/ssh/ssh_host_ed25519_key")
cp "$HOST_KEY_PUB" "$tmp/root/etc/ssh/ssh_host_ed25519_key.pub"

build_args=()
if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  build_args=(--build-on remote)
fi

PATH="$tmp/bin:$PATH" nixos-anywhere \
  --flake "$ROOT#mail" \
  --extra-files "$tmp/root" \
  ${build_args[@]+"${build_args[@]}"} \
  --target-host "$user@$ip"

# Pin the host key for all future connections.
echo "$name,$ip $(cut -d' ' -f1,2 "$HOST_KEY_PUB")" > "$KNOWN_HOSTS"
git add "$KNOWN_HOSTS" machine.json
info "Installed. Commit machine.json and known_hosts, then run 'just check'."
