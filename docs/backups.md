# Backups

Provider snapshots alone are not a backup: they live in the same account
as the server, so an account takeover, a `tofu destroy` or an attacker with
root can remove both. This setup backs up all mail with
[restic](https://restic.net) to an S3-compatible bucket at another company:
encrypted on the server before upload, deduplicated, and partly re-read
and verified after every backup.

What is backed up: every mailbox including Sieve filters (`/var/vmail`) and
Rspamd's learned spam data (`/var/lib/redis-rspamd`). Everything else
(configuration, DKIM keys, passwords) is in this repository.

## Setup

1. Create a bucket with a provider that is **not** your hosting provider,
   e.g. Backblaze B2, Wasabi or AWS S3, and an access key for it.
2. Put the repository in `settings.nix`, e.g.
   `backup.repository = "s3:https://s3.eu-central-003.backblazeb2.com/my-bucket/mail";`
3. `just backup-setup` stores the key in the secrets and generates the
   restic password. **Store that password in your password manager**; the
   backups cannot be restored without it.
4. Set `backup.enable = true`, then `just deploy` and `just backup-now`.

Backups run daily (`backup.schedule`), keep 7 daily, 5 weekly and 12
monthly snapshots (`backup.keep`), and verify 1% of the data on each run.
`just backup-snapshots` lists them.

## Protect the backups from the server itself

If the server is compromised, the attacker has its bucket key. With a
normal key they can delete every backup. To prevent that:

- **Backblaze B2:** enable *Object Lock* on the bucket with a default
  retention (e.g. 30 days), or create the server's key without the
  `deleteFiles` capability.
- **AWS S3 / Wasabi:** enable *Object Lock* (compliance mode), or give the
  server's key only `s3:PutObject`/`s3:GetObject`/`s3:ListBucket`.

Then set `backup.appendOnly = true`: the server stops pruning, and you run
`just backup-prune` from your own machine now and then, with a separate key
that may delete (export it as `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`).

## Restore

On the server (`just ssh`), the `restic-mail` command has the repository and
credentials configured:

```sh
restic-mail snapshots
# everything, into a scratch directory first
restic-mail restore latest --target /var/tmp/restore
# one mailbox
restic-mail restore latest --target /var/tmp/restore --include /var/vmail/example.com/alice
```

Then copy the Maildir folders back into `/var/vmail` with the ownership
`virtualMail:virtualMail` (`chown -R virtualMail:virtualMail ...`) and run
`doveadm force-resync -u <address> '*'`.

On a new server, install it first (`just install`), then restore; restic
needs only the repository URL, the bucket key and the restic password,
all of which are in this repository's secrets (and the password in your
password manager).
