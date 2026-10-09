variable "mail" {
  description = "Generated from settings.nix by `just tfvars`. Do not edit by hand."
  type        = any
}

variable "existing_ssh_key_fingerprints" {
  description = <<-EOT
    Fingerprints of SSH keys already uploaded to your DigitalOcean account.
    DigitalOcean refuses to upload the same key twice, so if the keys from
    settings.nix are already in your account, list their fingerprints here
    (e.g. in terraform.tfvars) instead.
  EOT
  type        = list(string)
  default     = []
}
