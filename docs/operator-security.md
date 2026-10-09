# Operator security checklist

The server is hardened, but whoever controls one of the accounts or machines
*around* it controls the mail. Each item below is a full compromise if lost.
Go through this list once, and again whenever something changes.

## Accounts

Turn on two-factor authentication, preferably a hardware key (FIDO2/WebAuthn,
e.g. a YubiKey) and otherwise TOTP. Never SMS. Store the recovery codes
offline.

- [ ] **Hosting provider** (OVHcloud, netcup CCP *and* SCP, UpCloud,
      Serverspace). Its web console, rescue mode, snapshots and "reinstall"
      button each give full access to the server and the disk.
- [ ] **Domain registrar.** Whoever can change the nameservers can redirect
      your mail and get valid certificates for your domains. Also turn on
      the registrar lock / transfer lock.
- [ ] **Cloudflare** (or wherever DNS is hosted). Same as the registrar.
- [ ] **GitHub** (or wherever this repository lives). With `autoUpgrade` on,
      push access is root on the server; protect the branch (required
      reviews, no force pushes).
- [ ] **The backup bucket provider** (see docs/backups.md).
- [ ] **The admin mailbox's own provider**, if `adminEmail` or your
      healthcheck alerts go to an external address.

## Your machine

Everything needed to take over the server lives on the machine you run
`just` from:

- **The age key** (`~/.config/sops/age/keys.txt`, or
  `~/Library/Application Support/sops/age/keys.txt` on macOS). It decrypts
  every secret, including the server's SSH host key. It is stored
  unencrypted by default. Better options:
  - Keep it on a hardware key with
    [age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey); sops
    supports age plugins, so `keys.txt` then only holds a stub and every
    decryption needs the key plugged in (and touched).
  - Or keep it in your password manager and hand it to sops on demand with
    `SOPS_AGE_KEY_CMD`, e.g.
    `export SOPS_AGE_KEY_CMD="op read op://Private/mailserver-age/key"`.
  - Either way, keep an offline backup of the key; without it you cannot
    change secrets or reinstall the server.
- **The root SSH key** (`settings.sshKeys`). Prefer a key that lives on a
  hardware token (`ssh-keygen -t ed25519-sk`), so that a stolen laptop or
  malware can't use it without the token.
- **Provider API credentials.** They are long-lived and powerful (the OVH
  key can order and terminate services). Keep them in your password manager
  and load them per shell (`op run`, `pass`, direnv with a password
  manager); don't put them in `~/.bashrc`. Give each key only what it needs
  (docs/providers.md lists the rights) and revoke keys you no longer use.
  The netcup token is stored encrypted in `secrets/secrets.yaml` by
  `just netcup-login` and never printed.
- **Full-disk encryption and a screen lock** on the machine itself.

## If something leaks

- **Age key or the repository with it:** generate a new age key, replace it in
  `.sops.yaml`, run `sops updatekeys secrets/*`, and then rotate the secrets
  themselves, because old ciphertexts stay in git history: every mailbox
  password (`just passwd`), the DKIM keys (`just add-domain` with a new
  selector, then remove the old one), the relay and backup credentials, and
  the Terraform state passphrase.
- **Server SSH host key / root on the server:** the attacker could decrypt all
  secrets. Generate a new host key (as `scripts/init.sh` does), replace the
  server's recipient in `.sops.yaml` with its `ssh-to-age` value, run
  `sops updatekeys secrets/*`, reinstall with `just install`, and rotate all
  secrets as above.
- **A provider API key:** revoke it in the provider's panel and create a new
  one.
- **A mailbox password:** `just passwd <address>` and `just deploy`; check
  `just logs` for what was sent from the account.
