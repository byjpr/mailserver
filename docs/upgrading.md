# Upgrading to a new NixOS release

Every NixOS release gets security updates for about seven months: until one
month after the next release. `lib/release.nix` records the release this
repository follows and its end of life.

**You will be warned** from 30 days before the end of life:

- by mail to `adminEmail`, weekly, from the server itself;
- by the weekly *Update flake inputs* workflow failing (GitHub mails the
  repository owner) and a warning on every CI run;
- by `just update`.

After the end of life, `just update` keeps working but no longer brings any
security fixes. Postfix, Dovecot, OpenSSH and the kernel stop being patched.

## How to upgrade

NixOS releases come out in May and November (`YY.05`, `YY.11`).
simple-nixos-mailserver publishes a matching branch shortly after each
release; wait for it before upgrading.

```sh
# e.g. to 26.11, supported until the end of June 2027
just upgrade-release 26.11 2027-06-30
```

This switches both `nixpkgs` and `simple-nixos-mailserver` in `flake.nix` to
the new branch, updates `lib/release.nix` and runs `nix flake update`. Then:

1. Read the [simple-nixos-mailserver release notes](https://nixos-mailserver.readthedocs.io/en/latest/release-notes.html)
   for the new release. If they ask you to raise `mailserver.stateVersion`
   (in `modules/mail.nix`), follow the linked migration steps **before**
   raising it; the build fails with instructions if one is required.
2. Read the [NixOS release notes](https://nixos.org/manual/nixos/stable/release-notes)
   for anything affecting Postfix, Dovecot, Rspamd, nginx or OpenSSH.
3. Never change `system.stateVersion` in `modules/hardening.nix`: it records
   the release the server was *installed* with, not the one it runs.
4. `just build`, then `just deploy`, then `just ssh reboot` (new kernel) and
   `just check`.
5. Commit and push.

If something goes wrong after deploying, roll back on the server with
`just ssh nixos-rebuild switch --rollback`, or choose the previous generation
in the boot menu from the provider's web console.
