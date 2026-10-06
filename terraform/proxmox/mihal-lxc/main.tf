locals {
  node_name = "proxmox"
  lan_cidr  = "192.168.0.0/16"
}

module "lxc" {
  source = "../../modules/proxmox-lxc"

  node_name        = local.node_name
  container_id     = 208
  hostname         = "mihal-lxc"
  template_file_id = var.lxc_template_file_id

  ip_address = "192.168.1.9/24"
  gateway    = "192.168.1.1"

  cpu_cores    = 1
  memory_mb    = 512
  disk_size_gb = 20

  # Filter this container's veth. Inert without the cluster-wide firewall switch,
  # which nocobase-lxc already turns on — Proxmox allows only one, so this dir
  # must not redeclare proxmox_virtual_environment_cluster_firewall.
  firewall_enabled = true

  ssh_public_keys = [var.ssh_public_key]

  password = var.host_password
}

resource "proxmox_virtual_environment_firewall_options" "mihal" {
  depends_on = [module.lxc]

  node_name    = local.node_name
  container_id = module.lxc.container_id

  enabled = true

  # Inbound stays open for LAN SSH and for WARP-routed traffic arriving over the
  # tunnel. Outbound falls through to the rule below; ACCEPT here is what lets
  # the container reach the internet once the LAN destination is dropped.
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"

  log_level_out = "info"
}

# Evaluated before output_policy. Return traffic for LAN-initiated connections
# (e.g. an SSH session from the LAN) is unaffected: the Proxmox firewall is
# stateful and accepts established/related before this rule runs.
resource "proxmox_virtual_environment_firewall_rules" "mihal" {
  depends_on = [proxmox_virtual_environment_firewall_options.mihal]

  node_name    = local.node_name
  container_id = module.lxc.container_id

  rule {
    type    = "out"
    action  = "DROP"
    comment = "No LAN access — internet only"
    dest    = local.lan_cidr
    log     = "info"
  }
}
