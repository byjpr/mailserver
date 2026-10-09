#!/usr/bin/env bash
# Build this flake and switch the running server to it.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

[[ -f "$KNOWN_HOSTS" ]] || die "known_hosts missing; has the server been installed ('just install')?"
target="root@$(fqdn)"

build_args=()
if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  # Can't build x86_64-linux locally: let the server build (mostly downloads).
  build_args=(--build-host "$target")
fi

NIX_SSHOPTS="$(ssh_opts)" nixos-rebuild-ng "${1:-switch}" \
  --flake "$ROOT#mail" \
  --target-host "$target" \
  ${build_args[@]+"${build_args[@]}"}

# A new kernel, initrd or kernel modules only take effect after a reboot.
# shellcheck disable=SC2046
if ssh $(ssh_opts) "$target" '
  for f in kernel initrd kernel-modules; do
    [ "$(readlink -f /run/booted-system/$f)" = "$(readlink -f /run/current-system/$f)" ] || exit 1
  done'; then
  info "Deployed. No reboot needed."
else
  info "Deployed. The kernel changed: run 'just reboot' (about a minute of downtime)."
fi
