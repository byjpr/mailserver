#!/usr/bin/env bash
# Reboot the server and wait for it to come back with its services running.
source "$(dirname "$0")/lib.sh"

target="root@$(fqdn)"
# shellcheck disable=SC2046
ssh $(ssh_opts) "$target" systemctl reboot || true
info "Rebooting $target; waiting for it to come back"
sleep 20
for _ in $(seq 60); do
  # shellcheck disable=SC2046
  if ssh $(ssh_opts) -o ConnectTimeout=5 "$target" \
       systemctl is-active --quiet postfix dovecot rspamd 2> /dev/null; then
    info "Back up; postfix, dovecot and rspamd are running."
    exit 0
  fi
  sleep 5
done
die "the server did not come back within 5 minutes; check the provider's web console"
