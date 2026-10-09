#!/usr/bin/env bash
# Obtain an offline refresh token for the netcup Server Control Panel API via
# the OAuth device flow, for the netcup Terraform step.
#
# The token is printed, not stored: put it in your password manager and
# export it as NETCUP_SCP_REFRESH_TOKEN before `just apply`. It stays valid as
# long as it is used at least once every 30 days; revoke it in the SCP under
# "Sessions" if it leaks.
source "$(dirname "$0")/lib.sh"

realm="https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect"

device="$(curl -fsS -X POST "$realm/auth/device" \
  -d client_id=scp -d 'scope=offline_access openid')"
code="$(jq -r .device_code <<< "$device")"
interval="$(jq -r '.interval // 5' <<< "$device")"

echo "Open this URL, log in with your netcup customer number and approve:"
echo "  $(jq -r .verification_uri_complete <<< "$device")"

while true; do
  sleep "$interval"
  response="$(curl -sS -X POST "$realm/token" \
    -d client_id=scp -d "device_code=$code" \
    -d grant_type=urn:ietf:params:oauth:grant-type:device_code)"
  case "$(jq -r '.error // empty' <<< "$response")" in
    "") break ;;
    authorization_pending) ;;
    slow_down) interval=$((interval + 5)) ;;
    *) die "login failed: $(jq -r '.error_description // .error' <<< "$response")" ;;
  esac
done

echo
echo "export NETCUP_SCP_REFRESH_TOKEN='$(jq -r .refresh_token <<< "$response")'"
