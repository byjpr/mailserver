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
resource "digitalocean_droplet" "mail" {
  # The droplet name doubles as the reverse DNS (PTR) record for both IPv4 and
  # IPv6, which receiving servers check. It must equal the mail host name.
  name   = local.m.fqdn
  region = local.m.droplet.region
  size   = local.m.droplet.size

  # Only the starting point; `just install` replaces it with NixOS.
  image = "ubuntu-24-04-x64"

  ipv6       = true
  monitoring = true
  backups    = local.m.droplet.backups
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

# --- DNS -------------------------------------------------------------------
resource "digitalocean_domain" "mail" {
  for_each = local.m.manageDns ? toset(local.m.domains) : toset([])
  name     = each.value
}

locals {
  host_records = [
    for type, ip in {
      A    = digitalocean_droplet.mail.ipv4_address
      AAAA = digitalocean_droplet.mail.ipv6_address
    } :
    {
      domain   = local.m.primaryDomain
      type     = type
      name     = local.m.hostname
      value    = ip
      priority = null
      weight   = null
      port     = null
      flags    = null
      tag      = null
    }
  ]

  all_records = concat(local.host_records, local.m.dnsRecords)
}

resource "digitalocean_record" "mail" {
  for_each = local.m.manageDns ? {
    for r in local.all_records : "${r.domain} ${r.type} ${r.name}" => r
  } : {}

  domain   = digitalocean_domain.mail[each.value.domain].id
  type     = each.value.type
  name     = each.value.name
  value    = each.value.value
  ttl      = 3600
  priority = each.value.priority
  weight   = each.value.weight
  port     = each.value.port
  flags    = each.value.flags
  tag      = each.value.tag
}
