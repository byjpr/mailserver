# mailserver

A small, hardened mail server you can deploy from scratch with a handful of
commands. It sends and receives mail for any number of domains, has no web UI,
and is configured entirely as code:

- **NixOS** with [simple-nixos-mailserver](https://gitlab.com/simple-nixos-mailserver/nixos-mailserver)
  (Postfix, Dovecot, Rspamd, Redis) for the server
- **OpenTofu/Terraform** for the server, its reverse DNS and every DNS record,
  on **OVHcloud, netcup, UpCloud or Serverspace** (DigitalOcean with a relay)
  and **Cloudflare** DNS, or any DNS host by hand
- **sops-nix** for secrets (password hashes, DKIM keys, relay credentials), encrypted in git
- **nixos-anywhere + disko** to turn a fresh server into NixOS in one step

You edit one file, [`settings.nix`](settings.nix). Both the server
configuration and the DNS records are generated from it, so they can't drift
apart.

It needs 2 GB of RAM, which costs €3–7 a month depending on the provider.
See [docs/providers.md](docs/providers.md) to choose one; OVHcloud and netcup
are the easiest, because they let you send on port 25 straight away.

## What you get

| | |
|---|---|
| **Receiving** | SMTP on port 25 with STARTTLS. Rspamd does spam filtering, greylisting, RBLs and SPF/DKIM/DMARC/ARC checks. |
| **Sending** | SMTP submission on port 465 (implicit TLS), with DKIM signing for every domain. Optionally through a relay. |
| **Reading** | IMAP on port 993 (implicit TLS) with quotas. Any mail client works: Thunderbird, Apple Mail, K-9/FairEmail, … |
| **TLS** | Let's Encrypt certificates, TLS 1.2+ with AEAD ciphers only, post-quantum hybrid key exchange. MTA-STS and TLS-RPT are published. Outbound mail validates DANE/MTA-STS. |
| **DNS** | MX, SPF (`-all`), DKIM (2048-bit RSA), DMARC (`p=reject`, strict alignment), MTA-STS, TLS-RPT, CAA, client autodiscovery SRV records, and reverse DNS for IPv4 and IPv6. |

See [docs/security.md](docs/security.md) for the threat model and every
hardening measure, including what stops spoofing and what stops the server
from being abused to send spam.

## Before you start

1. **Pick a provider** and set `provider` in `settings.nix`. Have its API
   credentials ready as environment variables
   ([docs/providers.md](docs/providers.md) lists them per provider).
2. **A domain**, with DNS either in Cloudflare (`export
   CLOUDFLARE_API_TOKEN=...`; Terraform creates the records) or anywhere else
   (`dns = "manual"`; you enter the records that `just dns` prints).
3. **Nix** with flakes on your machine (Linux or macOS). Everything else comes
   from the dev shell: run `nix develop`, or `direnv allow` if you use direnv.

## Setting up a new server

```sh
nix develop

# 1. Describe your setup: provider, domains, mailboxes, your SSH key.
$EDITOR settings.nix

# 2. Create your encryption key, the server's SSH host key and DKIM keys.
just init

# 3. Set a password for each mailbox.
just passwd admin@example.com

# 4. Lock dependency versions and commit everything (secrets are encrypted).
nix flake lock
git add -A && git commit -m "Configure mail server"

# 5. Create the server, its reverse DNS and the DNS records. Read the
#    "ACTION NEEDED" line at the end, if any (e.g. a support ticket).
just apply

# 6. Install NixOS on the server (wipes it), then commit what it recorded.
just install
git add -A && git commit -m "Install mail server"

# 7. Verify DNS, reverse DNS, TLS and MTA-STS from the outside.
just check
```

Then send a test mail to [mail-tester.com](https://www.mail-tester.com) and
run [internet.nl](https://internet.nl/test-mail/) against your domain.

**Back up your age key** (`~/.config/sops/age/keys.txt`, or
`~/Library/Application Support/sops/age/keys.txt` on macOS). Without it you
can't change secrets or reinstall the server from this repository.

### Mail client settings

| | Server | Port | Security | Username |
|---|---|---|---|---|
| Incoming (IMAP) | `mail.example.com` | 993 | SSL/TLS | full e-mail address |
| Outgoing (SMTP) | `mail.example.com` | 465 | SSL/TLS | full e-mail address |

## Day-to-day

| Task | How |
|---|---|
| Add a mailbox | Add it under `accounts` in `settings.nix`, run `just passwd <address>`, then `just deploy` |
| Change a password | `just passwd <address>` then `just deploy` |
| Add an alias | Add it to the mailbox's `aliases`, then `just deploy` |
| Forward an address elsewhere | Add it to `forwards`, then `just deploy` |
| Add a domain | Add it to `domains` and give it a `postmaster@` address, run `just add-domain <domain>`, then `just apply` (DNS) and `just deploy` |
| Rotate a DKIM key | `just add-domain <domain>` (new date-based selector), then `just apply && just deploy`. A few days later, delete the old `dkim/<domain>/<selector>.txt` and its entry in `just secrets`, then apply and deploy again |
| Send through a relay | Fill in `relay` in `settings.nix` and set `enable = true`, run `just relay-password`, then `just apply && just deploy` |
| Security updates | `just update && just deploy`. A weekly GitHub Action also opens a PR that updates `flake.lock`; or turn on `autoUpgrade` |
| Logs and queue | `just logs`, or `just ssh` |
| Rspamd web UI | `ssh -L 11334:/run/rspamd/worker-controller.sock root@mail.example.com`, then open http://localhost:11334 |

`just` with no arguments lists every command.

## Repository layout

```
settings.nix          the only file you normally edit
flake.nix             NixOS system + Terraform variable export + dev shell
modules/
  machine.nix         disk layout (disko), boot, networking (DHCP/static/cloud-init)
  hardening.nix       SSH, firewall, fail2ban, sysctls, auto-upgrades
  mail.nix            mail stack, anti-spoofing rules, rate limits, secrets
  relay.nix           optional outbound smarthost
  web.nix             Let's Encrypt + MTA-STS policy (nginx)
providers/            per-provider NixOS settings (network method, drivers)
lib/default.nix       derives DNS records etc. from settings.nix
lib/providers.nix     per-provider facts used by the scripts
dkim/                 public DKIM keys (generated, committed)
secrets/              sops-encrypted secrets + the server's public host key
infra/servers/<p>/    Terraform: server + reverse DNS, one directory per provider
infra/dns/cloudflare/ Terraform: all DNS records
scripts/              what the `just` commands run
tests/                fixtures for the CI build of an example configuration
machine.json          disk and network facts recorded by `just install`
known_hosts           the server's pinned SSH host key (written by `just install`)
```

## Backups and recovery

Provider backups differ: UpCloud's are enabled by `server.upcloud.backups`;
OVHcloud and netcup sell snapshots/backups as options in their panels;
Serverspace has snapshots in its panel. Mail lives in `/var/vmail`; for
off-site backups, add e.g. `services.restic.backups` pointing at an S3 bucket
(Backblaze B2, OVHcloud Object Storage, ...).

To rebuild from scratch, create a new server (`just apply`, after removing
the old one from the Terraform state), delete `machine.json`, and run
`just install`. Everything except the mail itself comes back from this
repository. The IP changes in that case; the DNS records follow automatically
when Terraform manages them.

## Limitations and notes

- **No virus scanning.** ClamAV needs 1–1.5 GB of RAM on its own. With 4 GB
  (e.g. OVHcloud VPS-1) you can set `mailserver.virusScanning = true` in
  `modules/mail.nix`.
- **No DANE for inbound mail.** MTA-STS covers the same downgrade attack.
  With DNSSEC enabled for your zone (Cloudflare supports it), publishing a
  TLSA record for the mail host would be a good addition.
- **A new IP has no reputation.** Expect some mail to land in spam folders at
  Gmail and Outlook during the first weeks, even with everything set up
  correctly. Check that your server's IP isn't on a blocklist
  ([MXToolbox](https://mxtoolbox.com/blacklists.aspx)) before you rely on
  it, and register with [Google Postmaster Tools](https://postmaster.google.com)
  and Microsoft SNDS. A relay avoids most of this.
- **Forwarding through a relay.** Some relays (Postmark, SES) only accept mail
  whose `From:` is one of your verified domains, so `forwards` of external
  mail may be refused while the relay is enabled.
- **The first install hasn't been tested on real servers of every
  provider.** If the server doesn't come back on the network after
  `just install`, boot the provider's rescue system (every provider here has
  one), compare `machine.json` with what `ip addr` shows there, fix it, and
  run `just install` again. There is no root password, so the provider's web
  console won't let you log in to the installed system.
- **DMARC `p=reject` on your domains** means mail that claims to be from your
  domain but didn't go through this server is rejected everywhere. If a domain
  also sends from somewhere else (a newsletter tool, a billing system),
  authorise that sender first or use `quarantine` until you have.
