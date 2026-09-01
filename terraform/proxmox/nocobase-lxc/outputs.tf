output "ssh_private_key" {
  description = "Dedicated private key for this container. Recover with: just output proxmox nocobase-lxc ssh_private_key"
  value       = tls_private_key.ssh.private_key_openssh
  sensitive   = true
}

output "ssh_public_key" {
  description = "Dedicated public key — safe to publish"
  value       = trimspace(tls_private_key.ssh.public_key_openssh)
}
