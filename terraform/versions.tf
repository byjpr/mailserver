terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.60"
    }
  }

  # State is kept locally in terraform/terraform.tfstate (git-ignored). It
  # contains no secrets beyond IDs and IPs, but losing it means importing the
  # resources again. For a team, use a remote backend such as DigitalOcean
  # Spaces (S3-compatible):
  #
  # backend "s3" {
  #   endpoints                   = { s3 = "https://fra1.digitaloceanspaces.com" }
  #   bucket                      = "my-terraform-state"
  #   key                         = "mailserver/terraform.tfstate"
  #   region                      = "us-east-1"
  #   skip_credentials_validation = true
  #   skip_requesting_account_id  = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   skip_s3_checksum            = true
  # }
}

# Reads the API token from the DIGITALOCEAN_TOKEN environment variable.
provider "digitalocean" {}
