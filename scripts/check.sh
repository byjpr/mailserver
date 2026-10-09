#!/usr/bin/env bash
# shellcheck disable=SC2015  # ok() always succeeds
# Verify the public DNS and TLS setup of the server from the outside.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

resolver="${RESOLVER:-1.1.1.1}"
name="$(fqdn)"
failures=0

ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; failures=$((failures + 1)); }
q() { dig +short "@$resolver" "$@" | sed 's/" "//g; s/"//g'; }

echo "Mail host $name"
ip4="$(q A "$name" | tail -n1)"
ip6="$(q AAAA "$name" | tail -n1)"
[[ -n "$ip4" ]] && ok "A $ip4" || bad "no A record for $name"
if tfvars | jq -e .providerInfo.hasIPv6 > /dev/null; then
  [[ -n "$ip6" ]] && ok "AAAA $ip6" || bad "no AAAA record for $name"
fi
for ip in $ip4 $ip6; do
  ptr="$(q -x "$ip" | head -n1)"
  [[ "$ptr" == "$name." ]] && ok "PTR $ip -> $ptr" \
    || bad "PTR for $ip is '$ptr', expected '$name.' (see docs/providers.md)"
done

for port in 465 993; do
  if echo | openssl s_client -connect "$name:$port" -servername "$name" -verify_return_error \
       -verify_hostname "$name" > /dev/null 2>&1; then
    ok "TLS certificate valid on port $port"
  else
    bad "TLS on port $port (is the server up and the certificate issued?)"
  fi
done
if echo QUIT | timeout 15 openssl s_client -starttls smtp -connect "$name:25" -verify_return_error \
     -verify_hostname "$name" > /dev/null 2>&1; then
  ok "SMTP STARTTLS on port 25"
else
  bad "SMTP STARTTLS on port 25 (your own ISP may block outbound port 25)"
fi

# Outbound SMTP, tested from the server itself: providers block port 25
# (netcup's "Mail block" policy, UpCloud, OVH's anti-spam), and nothing else
# would tell you until mail silently stops arriving.
if [[ -f "$KNOWN_HOSTS" ]]; then
  echo "Outbound SMTP (from the server)"
  # shellcheck disable=SC2046
  results="$(ssh $(ssh_opts) -o ConnectTimeout=10 "root@$name" '
    for family in 4 6; do
      if [ $family = 6 ] && [ -z "$(ip -6 route show default)" ]; then echo "6 none"; continue; fi
      ip=$(getent ahostsv$family gmail-smtp-in.l.google.com | awk "NR==1{print \$1}")
      if [ -z "$ip" ]; then echo "$family none"; continue; fi
      banner=$(timeout 10 bash -c "exec 3<>/dev/tcp/$ip/25 && head -c 3 <&3" 2> /dev/null)
      echo "$family ${banner:-fail} $ip"
    done' 2> /dev/null || echo "ssh failed")"
  while read -r family status target; do
    case "$status" in
      220) ok "port 25 open over IPv$family (Gmail answered from $target)" ;;
      none) [[ "$family" == 6 ]] && ok "no IPv6 route to test (IPv4-only server)" || bad "cannot resolve Gmail's MX over IPv$family" ;;
      failed) bad "could not ssh to $name to test outbound SMTP" ;;
      *) if [[ "$(setting relay.enable)" == true ]]; then
           ok "port 25 over IPv$family is blocked, but relay.enable is set"
         else
           bad "port 25 to $target (IPv$family) is BLOCKED: ask the provider to open it, or set relay.enable"
         fi ;;
    esac
  done <<< "${results/ssh failed/0 failed}"
fi

for domain in $(setting domains | jq -r '.[]'); do
  echo "Domain $domain"
  [[ "$(q MX "$domain")" == "10 $name." ]] && ok "MX -> $name" || bad "MX: '$(q MX "$domain")'"
  spf="$(q TXT "$domain" | grep '^v=spf1' || true)"
  [[ "$spf" == *"-all" ]] && ok "SPF $spf" || bad "SPF: '$spf'"
  dmarc="$(q TXT "_dmarc.$domain")"
  [[ "$dmarc" == v=DMARC1* ]] && ok "DMARC $dmarc" || bad "DMARC: '$dmarc'"
  for f in dkim/"$domain"/*.txt; do
    [[ -f "$f" ]] || { bad "no DKIM key in dkim/$domain"; continue; }
    selector="$(basename "$f" .txt)"
    [[ "$(q TXT "$selector._domainkey.$domain")" == "$(cat "$f")" ]] \
      && ok "DKIM selector $selector" || bad "DKIM $selector._domainkey.$domain does not match $f"
  done
  [[ "$(q TXT "_mta-sts.$domain")" == v=STSv1* ]] && ok "MTA-STS record" || bad "MTA-STS TXT record"
  policy="$(curl -fsS --max-time 10 "https://mta-sts.$domain/.well-known/mta-sts.txt" || true)"
  [[ "$policy" == *"mx: $name"* ]] && ok "MTA-STS policy served" || bad "MTA-STS policy at https://mta-sts.$domain/"
  [[ "$(q TXT "_smtp._tls.$domain")" == v=TLSRPTv1* ]] && ok "TLS-RPT record" || bad "TLS-RPT record"
done

echo
if (( failures == 0 )); then
  echo "All checks passed. For an end-to-end test, send a mail to https://www.mail-tester.com"
  echo "and check https://internet.nl/test-mail/ ."
else
  echo "$failures check(s) failed. DNS changes can take a while to propagate."
  exit 1
fi
