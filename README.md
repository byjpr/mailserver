# mailserver

A small, hardened mail server you can deploy from scratch with a handful of
commands. It sends and receives mail for any number of domains, has no web UI,
and is configured entirely as code:

- **NixOS** with [simple-nixos-mailserver](https://gitlab.com/simple-nixos-mailserver/nixos-mailserver)
  (Postfix, Dovecot, Rspamd, Redis) for the server
- **OpenTofu/Terraform** for the DigitalOcean droplet, firewall and every DNS record
- **sops-nix** for secrets (password hashes, DKIM keys, relay credentials), encrypted in git
- **nixos-anywhere + disko** to turn a fresh droplet into NixOS in one step

You edit one file, [`settings.nix`](settings.nix). Both the server
configuration and the DNS records are generated from it, so they can't drift
apart.

It runs on the `s-1vcpu-1gb` droplet (about $6/month, plus $1.20 for backups).

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

1. **Port 25.** DigitalOcean blocks outbound SMTP on most accounts. Open a
   support ticket and ask for port 25 to be unblocked for a mail server, and
   mention that SPF, DKIM, DMARC and reverse DNS are set up. If they refuse,
   enable the relay in `settings.nix` (Postmark, Amazon SES, Mailgun and
   others work).
2. **A domain** whose DNS you can point at DigitalOcean (set its NS records at
   your registrar to `ns1/ns2/ns3.digitalocean.com`). Alternatively, set
   `manageDns = false` and create the records yourself from `just dns`.
3. **Nix** with flakes on your machine (Linux or macOS). Everything else comes
   from the dev shell: run `nix develop`, or `direnv allow` if you use direnv.
4. A DigitalOcean API token with write access:
   `export DIGITALOCEAN_TOKEN=dop_v1_...`

## Setting up a new server

```sh
nix develop

# 1. Describe your setup: domains, mailboxes, your SSH key, region.
$EDITOR settings.nix

# 2. Create your encryption key, the server's SSH host key and DKIM keys.
just init

# 3. Set a password for each mailbox.
just passwd admin@example.com

# 4. Lock dependency versions and commit everything (secrets are encrypted).
nix flake lock
git add -A && git commit -m "Configure mail server"

# 5. Create the droplet, firewall and DNS records.
just apply
#    -> point your domain's NS records at DigitalOcean now if you haven't,
#       and wait until `dig mail.example.com` returns the droplet's IP.

# 6. Install NixOS on the droplet (wipes it).
just install
#    -> if this runs out of memory, temporarily resize the droplet to 2 GB
#       ("CPU and RAM only" in the DigitalOcean panel), install, then resize
#       back down.

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
  digitalocean.nix    disk layout (disko), boot, networking via DO metadata
  hardening.nix       SSH, firewall, fail2ban, sysctls, auto-upgrades
  mail.nix            mail stack, anti-spoofing rules, rate limits, secrets
  relay.nix           optional outbound smarthost
  web.nix             Let's Encrypt + MTA-STS policy (nginx)
lib/default.nix       derives DNS records etc. from settings.nix
dkim/                 public DKIM keys (generated, committed)
secrets/              sops-encrypted secrets + the server's public host key
terraform/            droplet, cloud firewall, DNS zones and records
scripts/              what the `just` commands run
tests/                fixtures for the CI build of an example configuration
known_hosts           the server's pinned SSH host key (written by `just install`)
```

## Backups and recovery

Droplet backups (`droplet.backups = true`) take a weekly snapshot of the whole
disk. Mail lives in `/var/vmail`; for more frequent off-site backups, add
e.g. `services.restic.backups` pointing at an S3 bucket (DigitalOcean Spaces,
Backblaze B2).

To rebuild from scratch, restore the droplet from a backup, or create a new
one (`just apply`, after removing the old droplet from the Terraform state)
and run `just install`. Everything except the mail itself comes back from
this repository. The droplet's IP changes in that case; the DNS records
follow automatically through Terraform.

## Limitations and notes

- **No virus scanning.** ClamAV needs more than 1 GB of RAM. To enable it, use
  a 2 GB droplet and set `mailserver.virusScanning = true` in
  `modules/mail.nix`.
- **No DNSSEC/DANE for your own domains.** DigitalOcean DNS doesn't support
  DNSSEC. MTA-STS covers the same downgrade attack for inbound mail. If your
  DNS provider supports DNSSEC, publishing a TLSA record is a good addition.
- **A new IP has no reputation.** Expect some mail to land in spam folders at
  Gmail and Outlook during the first weeks, even with everything set up
  correctly. Check that your droplet's IP isn't on a blocklist
  ([MXToolbox](https://mxtoolbox.com/blacklists.aspx)) before you rely on
  it, and register with [Google Postmaster Tools](https://postmaster.google.com)
  and Microsoft SNDS. A relay avoids most of this.
- **Forwarding through a relay.** Some relays (Postmark, SES) only accept mail
  whose `From:` is one of your verified domains, so `forwards` of external
  mail may be refused while the relay is enabled.
- **The first install hasn't been tested on every DigitalOcean region.** If
  the droplet doesn't come back on the network after `just install`, open the
  droplet's Recovery Console in the DigitalOcean panel and check
  `journalctl -u cloud-init-local`.
- **DMARC `p=reject` on your domains** means mail that claims to be from your
  domain but didn't go through this server is rejected everywhere. If a domain
  also sends from somewhere else (a newsletter tool, a billing system),
  authorise that sender first or use `quarantine` until you have.
