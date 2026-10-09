locals {
  m = var.mail

  upload_ssh_keys = length(var.existing_ssh_key_fingerprints) == 0
}

# --- SSH keys used for the very first boot ----------------------------------
# Only needed so nixos-anywhere can log into the initial Ubuntu image. After
# installation, root's authorized keys come from settings.nix.
resource "digitalocean_ssh_key" "admin" {
  for_each   = local.upload_ssh_keys ? { for i, k in local.m.sshKeys : tostring(i) => k } : {}
  name       = "${local.m.fqdn}-${each.key}"
  public_key = each.value
}

# --- The server --------------------------------------------------------------
# NOTE: DigitalOcean blocks outbound port 25 on most accounts and rarely lifts
# it. Only use this provider together with settings.relay.
resource "digitalocean_droplet" "mail" {
  # The droplet name doubles as the reverse DNS (PTR) record for both IPv4 and
  # IPv6, which receiving servers check. It must equal the mail host name.
  name   = local.m.fqdn
  region = local.m.server.region
  size   = local.m.server.size

  # Only the starting point; `just install` replaces it with NixOS.
  image = "ubuntu-24-04-x64"

  ipv6       = true
  monitoring = true
  backups    = local.m.server.backups
  ssh_keys = local.upload_ssh_keys ? [
    for k in digitalocean_ssh_key.admin : k.fingerprint
  ] : var.existing_ssh_key_fingerprints

  lifecycle {
    # Changing these would rebuild the droplet and destroy all mail.
    ignore_changes = [image, ssh_keys]
    # Remove this line deliberately if you really want to destroy the server.
    prevent_destroy = true
  }
}

# --- Cloud firewall (in front of the host firewall) ---------------------------
resource "digitalocean_firewall" "mail" {
  name        = replace(local.m.fqdn, ".", "-")
  droplet_ids = [digitalocean_droplet.mail.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = local.m.sshAllowedCidrs
  }

  dynamic "inbound_rule" {
    # SMTP, HTTP (ACME), HTTPS (MTA-STS), SMTP submission (TLS), IMAP (TLS)
    for_each = ["25", "80", "443", "465", "993"]
    content {
      protocol         = "tcp"
      port_range       = inbound_rule.value
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  dynamic "outbound_rule" {
    for_each = ["tcp", "udp"]
    content {
      protocol              = outbound_rule.value
      port_range            = "1-65535"
      destination_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
