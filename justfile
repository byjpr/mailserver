# Run `nix develop` first (or use direnv) to get every tool used here.

set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# One-time: create encryption keys, the server's SSH host key and DKIM keys
init:
    scripts/init.sh

# Generate a DKIM key for a (new) domain; add it to settings.nix too
add-domain domain selector="":
    scripts/add-domain.sh {{domain}} {{selector}}

# Set a mailbox password (add --random to generate one)
passwd address *flags:
    scripts/passwd.sh {{address}} {{flags}}

# Store the password for the outbound relay (settings.relay)
relay-password:
    scripts/relay-password.sh

# Edit the encrypted secrets directly
secrets:
    sops secrets/secrets.yaml

# Show the server changes Terraform would make
plan:
    scripts/apply.sh plan

# Create / update the server, its reverse DNS and all DNS records
apply:
    scripts/apply.sh

# Get an API token for the netcup Server Control Panel (provider = netcup)
netcup-login:
    scripts/netcup-login.sh

# First install: wipe the server and install NixOS on it
install:
    scripts/install.sh

# Build the configuration locally without deploying (catches errors early)
build:
    nix build .#nixosConfigurations.mail.config.system.build.toplevel --no-link --print-out-paths

# Push the current configuration to the server (or: just deploy dry-activate)
deploy action="switch":
    scripts/deploy.sh {{action}}

# Update nixpkgs and the other inputs (then: just deploy)
update:
    nix flake update

# Print the DNS records (for dns = "manual")
dns:
    scripts/dns.sh

# Check DNS, reverse DNS, TLS and MTA-STS from the outside
check:
    scripts/check.sh

# Open a root shell on the server, or run a command there
ssh *command:
    source scripts/lib.sh && ssh $(ssh_opts) "root@$(fqdn)" {{command}}

# Show the mail queue and recent mail log on the server
logs:
    just ssh "'postqueue -p; journalctl -u postfix -u dovecot -u rspamd -n 100 --no-pager'"

fmt:
    nix fmt
    tofu fmt -recursive infra
