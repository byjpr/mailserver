# First install: verification checklist

Several parts of this setup are specific to each provider and can only be
fully verified on a real server: the static network configuration, the first
boot, outbound SMTP, reverse DNS, and (with `relay`) the relay credentials.
Go through this list after `just install` on a new provider or region, and
after major changes. It takes about fifteen minutes.

## Right after `just install`

- [ ] The server comes back: `just status` shows postfix, dovecot, rspamd,
      redis-rspamd, nginx, kresd@1 and fail2ban as `active`, and no failed
      units. If SSH doesn't come back at all, see "If the server is
      unreachable" below.
- [ ] Networking is right: `just ssh ip -br addr` shows the addresses from
      `machine.json`, and `just ssh ping -c1 -6 google.com` works (skip on
      IPv4-only providers).
- [ ] Secrets were decrypted: `just ssh ls /run/secrets/` lists `mailbox`,
      `dkim` and (if used) `relay` / `backup`.
- [ ] The certificate was issued: `just status` shows a Let's Encrypt
      certificate, not "missing". If it failed, DNS probably wasn't live yet;
      retry with `just ssh systemctl start acme-order-renew-mail.example.com.service`
      (with your mail host name).

## From the outside

- [ ] `just check` passes: DNS records, reverse DNS for IPv4 and IPv6, TLS
      on 25/465/993, MTA-STS policy, and outbound port 25 from the server.
- [ ] Inbound: send a mail from an external account (Gmail, Outlook) to one
      of your addresses; it arrives (check `just logs` if not; greylisting
      can delay the first one by a few minutes).
- [ ] Outbound: send from a mail client (port 465, SSL/TLS) to the external
      account. In Gmail, "Show original" must show `SPF: PASS`,
      `DKIM: PASS` and `DMARC: PASS`, and it must land in the inbox.
- [ ] Score: send a message to the address given by
      [mail-tester.com](https://www.mail-tester.com) and aim for 10/10.
- [ ] [internet.nl mail test](https://internet.nl/test-mail/) for your domain:
      everything green except DNSSEC/DANE if your DNS host lacks them.

## With a relay (`relay.enable = true`)

- [ ] Outbound mail goes through the relay: `just logs` shows
      `relay=[smtp.your-relay]:587` and `status=sent`. A
      `SASL authentication failed` or `unable to read SASL password map`
      message means wrong credentials or file permissions:
      `just ssh ls -l /run/secrets/rendered/` should show
      `postfix-relay-credentials` as `root postfix -r--r-----`.

## OVHcloud only

- [ ] `just apply` ended without errors after the VPS reinstall step, and
      `just install` could log in as `debian`. If the reinstall step timed
      out, finish it in the OVH Control Panel (VPS > Reinstall, with your SSH
      key) and re-run `just apply`.

## If the server is unreachable

There is no root password, so the provider's web console can't be used to
log in to NixOS. Instead:

1. Boot the provider's rescue system (all supported providers have one).
2. Mount the disk and look at `/var/log/journal` with
   `journalctl -D /mnt/var/log/journal -b -1`, and compare
   `ip addr` in the rescue system with `machine.json`.
3. Fix `machine.json` (or the provider module), commit, and run
   `just install` again. It wipes the disk, so only do this before you have
   mail on the server, or restore from backup afterwards.

Please report what you had to change, so the provider modules can be fixed
for everyone.
