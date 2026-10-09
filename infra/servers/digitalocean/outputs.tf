output "ipv4" {
  value = digitalocean_droplet.mail.ipv4_address
}

output "ipv6" {
  value = digitalocean_droplet.mail.ipv6_address
}
