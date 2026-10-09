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
