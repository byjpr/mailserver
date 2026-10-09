#!/usr/bin/env bash
# Quick health overview of the installed server.
source "$(dirname "$0")/lib.sh"

# shellcheck disable=SC2046
ssh $(ssh_opts) "root@$(fqdn)" bash -s <<'REMOTE'
for unit in postfix dovecot rspamd redis-rspamd nginx kresd@1 fail2ban; do
  printf '%-14s %s\n' "$unit" "$(systemctl is-active "$unit")"
done
echo
failed="$(systemctl --failed --no-legend --plain)"
echo "failed units:  ${failed:-none}"
echo "mail queue:    $(postqueue -j 2> /dev/null | wc -l) message(s)"
cert="/var/lib/acme/$(hostname -f)/cert.pem"
echo "certificate:   $(openssl x509 -noout -enddate -in "$cert" 2> /dev/null || echo missing)"
echo "disk /:        $(df -h --output=pcent,avail / | tail -n1)"
for f in kernel initrd kernel-modules; do
  [ "$(readlink -f /run/booted-system/$f)" = "$(readlink -f /run/current-system/$f)" ] || { echo "reboot:        needed (kernel changed)"; break; }
done
echo "uptime:       $(uptime)"
REMOTE
