resource "proxmox_virtual_environment_firewall_options" "cloudflared" {
  node_name = "proxmox"
  vm_id     = module.lxc.container_id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "cloudflared" {
  node_name = "proxmox"
  vm_id     = module.lxc.container_id

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.1.120"
    comment = "allow outbound to k3s"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "DROP"
    dest    = "192.168.1.0/24"
    comment = "block outbound to rest of LAN"
    enabled = true
  }

  depends_on = [proxmox_virtual_environment_firewall_options.cloudflared]
}