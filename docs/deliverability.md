# Mail that gets rejected on purpose, and how to handle it

This setup is strict in both directions. That stops spoofing, but a few
legitimate kinds of mail need a deliberate decision.

## Sending: apps and services that send "as" your domain

Your domains publish SPF `-all` and DMARC `p=reject` with strict alignment.
Receivers therefore reject any mail claiming to be from your domain unless it
was either sent through this server, or sent by a service you authorised.
This server also refuses unauthenticated mail on port 25 that claims to come
from one of your own domains.

That affects, for example: a contact form on your website, a NAS or printer
sending alerts, a newsletter tool, a helpdesk, invoicing software.

**Option 1: send through this server.** Create a dedicated account that can
only send:

```nix
accounts."website@example.com" = {
  sendOnly = true;
};
```

Then `just passwd website@example.com --random`, `just deploy`, and configure
the app for SMTP with `mail.example.com`, port **465**, SSL/TLS, that address
and password. The mail is DKIM-signed and passes DMARC everywhere.
Authenticated accounts can only send as their own address and aliases.

**Option 2: authorise the service.** For services that must send from their
own servers (most newsletter tools):

- Prefer the service's *custom DKIM* feature for your domain: it gives you a
  DKIM record to publish (a TXT or CNAME at `<selector>._domainkey`), and its
  mail then passes DMARC through DKIM alignment. Add the record at your DNS
  host; records you add yourself in Cloudflare are left alone by this
  repository's Terraform.
- If it can only align SPF, add its include to the SPF record. There is one
  slot for this today, `relay.spfInclude`, and SPF allows at most 10 DNS
  lookups in total.
- Use a subdomain for bulk mail (`news.example.com`) where you can, so a
  problem there doesn't affect your main domain's reputation.

**Rolling out on a domain that already sends from elsewhere:** start with
`dmarc.policy = "none"` and read the aggregate reports arriving at
`dmarc.reportAddress` for a few weeks: they list every source sending as your
domain. Authorise the legitimate ones, then move to `"quarantine"` and finally
`"reject"`.

## Receiving: DMARC enforcement and mailing lists

Incoming mail is checked against the sender's DMARC policy and, with
`dmarc.enforceInbound = true` (the default), that policy is enforced: mail
that fails a `p=reject` policy is rejected, mail failing `p=quarantine` goes
to Junk. This is what keeps out mail spoofing your bank, PayPal or your own
colleagues at other companies.

The cost: some **mailing lists** add a subject tag or footer, which breaks
the original sender's DKIM signature. Many lists (Google Groups, and Mailman
with DMARC mitigation turned on) rewrite the `From:` address of such posts
to their own; if a list doesn't, a post by someone at a `p=reject` domain
(Yahoo, AOL, many companies) fails DMARC and is rejected by this server, as
Gmail and Outlook would do too.

If that hurts more than it helps for you, set `dmarc.enforceInbound = false`:
DMARC failures then only add to the spam score. Gmail-style behaviour (the
default) is recommended.
