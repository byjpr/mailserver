variable "mail" {
  description = "Generated from settings.nix by `just tfvars` (settings.auto.tfvars.json). Do not edit by hand."
  type = object({
    hostname        = string
    primaryDomain   = string
    fqdn            = string
    domains         = list(string)
    sshKeys         = list(string)
    sshAllowedCidrs = list(string)
    manageDns       = bool
    droplet = object({
      region  = string
      size    = string
      backups = bool
    })
    dnsRecords = list(object({
      domain   = string
      type     = string
      name     = string
      value    = string
      priority = optional(number)
      weight   = optional(number)
      port     = optional(number)
      flags    = optional(number)
      tag      = optional(string)
    }))
  })
}

variable "existing_ssh_key_fingerprints" {
  description = <<-EOT
    Fingerprints of SSH keys already uploaded to your DigitalOcean account.
    DigitalOcean refuses to upload the same key twice, so if the keys from
    settings.nix are already in your account, list their fingerprints here
    (e.g. in terraform/terraform.tfvars) instead.
  EOT
  type        = list(string)
  default     = []
}
