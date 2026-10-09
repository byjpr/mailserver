output "ipv4" {
  value = digitalocean_droplet.mail.ipv4_address
}

output "ipv6" {
  value = digitalocean_droplet.mail.ipv6_address
}

output "fqdn" {
  value = local.m.fqdn
}

output "nameservers" {
  description = "Point each domain's NS records at these at your registrar."
  value       = local.m.manageDns ? ["ns1.digitalocean.com", "ns2.digitalocean.com", "ns3.digitalocean.com"] : []
}
