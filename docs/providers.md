# Hosting providers

Pick one with `provider` in `settings.nix`; its size and location go under
`server.<provider>`. Everything else (mail setup, hardening, DNS) is the same
on every provider.

| | OVHcloud VPS | netcup | UpCloud | Serverspace | DigitalOcean |
|---|---|---|---|---|---|
| **Outbound port 25** | Open | Opened by `just apply` | Blocked until Support lifts it | "May be restricted"; ask Support | Blocked |
| **Reverse DNS** | Terraform (after DNS resolves) | Terraform | `just apply` (API call) | Support ticket | Automatic |
| **IPv6** | Yes (/128, static) | Yes (/64, static) | Yes (DHCP/RA) | No | Yes |
| **Server creation** | Terraform (places an order) | Manual order, adopted by ID | Terraform | Terraform | Terraform |
| **Cheapest suitable plan** | VPS-1 2027: 2 vCPU, 4 GB, about €4.50/month | VPS nano G11.5s: 2 vCPU, 2 GB, about €3.10/month (6-month term) | Starter 1 CPU, 2 GB, about €6/month | 1 vCPU, 2 GB, about €7/month | 1 vCPU, 2 GB, about $12/month |
| **Network firewall** | none used (host nftables) | turned off (host nftables) | not used (host nftables) | none (host nftables) | Cloud firewall + nftables |

Prices exclude VAT and were checked in October 2026. 2 GB of RAM is the
minimum: the installer (nixos-anywhere) needs about 1.5 GB.

**Recommendation:** OVHcloud or netcup. Both let you send mail on port 25
without asking anyone, set reverse DNS through the API, and give you IPv6.

All providers' network firewalls are either missing, stateless (UpCloud) or
SMTP-blocking by default (netcup), so the host firewall (nftables) is the one
that counts everywhere. It only opens 25, 80, 443, 465, 993 and SSH, and SSH
only from `sshAllowedCidrs`.

## How the pieces fit

1. `just apply` runs `infra/servers/<provider>` (server, reverse DNS where
   possible), then `infra/dns/cloudflare` (or prints the records for
   `dns = "manual"`), then finishes reverse DNS for providers that check the
   forward record first. It prints anything you still need to do by hand.
2. `just install` logs into the provider's stock Debian/Ubuntu image, records
   the root disk and the network configuration in `machine.json`, and replaces
   the system with NixOS. For providers without DHCP, NixOS configures exactly
   those addresses statically (matched to the NIC's MAC address).
3. Commit `machine.json` and `known_hosts` afterwards.

## OVHcloud (`provider = "ovh"`)

**Credentials:** create an API application at
<https://eu.api.ovh.com/createToken/> (or the `ca`/`us` equivalent) with
`GET/POST/PUT /vps/*`, `GET/POST /ip/*`, `GET /me*`, and the order routes
(`/order/*`, `/me/order/*`, `GET/POST/DELETE`). Then:

```sh
export OVH_ENDPOINT=ovh-eu
export OVH_APPLICATION_KEY=... OVH_APPLICATION_SECRET=... OVH_CONSUMER_KEY=...
```

- `just apply` **places an order** on your account (needs a default payment
  method: card or SEPA direct debit). OVH then delivers the VPS, and the step
  reinstalls it with your first SSH key (`scripts/ovh-vps-rebuild.py`). This
  can take 10–20 minutes.
- Don't pick a plan ending in `.LZ` (Local Zone): those can never send mail.
- Reverse DNS is set in a second pass, once your A/AAAA records resolve
  (OVH checks that they point back).
- OVH monitors outgoing mail; an IP that sends spam gets port 25 blocked
  (Control Panel > Network > IP > "Anti-spam unblocking").
- The stock image's user is `debian`, which `just install` logs in as and
  uses `sudo`.

## netcup (`provider = "netcup"`)

netcup has no API for creating servers.

1. Order a VPS (nano G11.5s or larger; pico has too little RAM) and add your
   SSH key for root when it is set up (SCP > Media > Images > reinstall
   "Debian" with your key, or copy it in with the emailed password).
2. Put the server ID (SCP > server > General) into `server.netcup.serverId`.
3. `just netcup-login`. The resulting API token is stored encrypted in
   `secrets/secrets.yaml` (never printed) and used by `just apply`. It stays
   valid if used at least once every 30 days.

`just apply` then sets the host name and the reverse DNS for IPv4 and the
first address of your IPv6 /64, and **turns off netcup's network firewall**,
whose default "netcup Mail block" policy blocks SMTP in both directions.
The static IPv4/IPv6 configuration comes from the SCP API.

## UpCloud (`provider = "upcloud"`)

**Credentials:** create an API sub-account (Control Panel > People) with API
access only, then `export UPCLOUD_USERNAME=... UPCLOUD_PASSWORD=...`.

- **Port 25 is blocked on every account** until Support lifts it. They ask for
  identification and your use case. Until then, use `relay`.
- Free-trial accounts block port 25 inbound too; upgrade first.
- Reverse DNS is set through the API by `just apply`, since UpCloud's
  Terraform provider can't manage it.
- UpCloud's network firewall is stateless (every reply needs its own rule),
  so it's left off in favour of the host firewall.

## Serverspace (`provider = "serverspace"`)

**Credentials:** create an API key (panel > Automation), then
`export SERVERSPACE_KEY=...`.

- **No IPv6**, so the server is IPv4-only.
- **Reverse DNS only by support ticket**; `just apply` reminds you.
- Port 25 "may be restricted at the network level": ask Support to confirm
  it's open, or use `relay`.
- The Terraform provider hasn't had a release since January 2025.
- The Amsterdam location has been without power since 15 September 2026; pick
  New Jersey, Toronto or another location.
- Image IDs change over time. If `Debian-12-X64` is rejected, list them:
  `curl -H "X-API-KEY: $SERVERSPACE_KEY" https://api.serverspace.io/api/v1/images`.

## DigitalOcean (`provider = "digitalocean"`)

`export DIGITALOCEAN_TOKEN=...`. Outbound port 25 is blocked and rarely
lifted, so set `relay.enable = true`. Reverse DNS follows the droplet name
automatically.

## DNS (`dns` in settings.nix)

- `"cloudflare"`: `export CLOUDFLARE_API_TOKEN=...` with *Zone:DNS:Edit* and
  *Zone:Zone:Read* for your domains. The zones must already exist in
  Cloudflare (add the domain, then switch its nameservers at your registrar).
  Records are never proxied. Cloudflare also supports DNSSEC, so turn it on
  for your zones.
- `"manual"`: `just dns` prints every record in zone-file notation. Long DKIM
  TXT values may need splitting into 255-character strings, depending on your
  DNS host. `just check` verifies what's published.

## Adding another provider

1. `infra/servers/<name>/main.tf`: create the server, set reverse DNS if the
   API allows, and output `ipv4` and `ipv6` (an empty string if none). Output
   `network` too (as in `netcup`) if the API knows addresses the stock image
   doesn't configure.
2. `providers/<name>.nix`: the network method (`dhcp`, `static` or
   `cloud-init`) and any kernel modules.
3. An entry in `lib/providers.nix`, and a `server.<name>` block in
   `settings.nix`.
