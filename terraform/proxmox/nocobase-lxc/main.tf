locals {
  node_name = "proxmox"
  lan_cidr  = "192.168.0.0/16"
  key_dir   = "${path.module}/.ssh"
}

# Dedicated keypair for this container, generated on first apply.
#
# The private key is stored in the Terraform state on R2 — treat that state as
# the secret of record. The files below are a local convenience copy; a CI apply
# writes them into the runner's throwaway workspace, so recover them instead with
#   just output proxmox nocobase-lxc ssh_private_key
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "ssh_private_key" {
  filename             = "${local.key_dir}/id_ed25519"
  content              = tls_private_key.ssh.private_key_openssh
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_file" "ssh_public_key" {
  filename             = "${local.key_dir}/id_ed25519.pub"
  content              = "${trimspace(tls_private_key.ssh.public_key_openssh)} nocobase@deepcraft\n"
  file_permission      = "0644"
  directory_permission = "0700"
}

module "lxc" {
  source = "../../modules/proxmox-lxc"

  node_name        = local.node_name
  container_id     = 207
  hostname         = "nocobase"
  template_file_id = var.lxc_template_file_id

  ip_address = "192.168.1.5/24"
  gateway    = "192.168.1.1"

  cpu_cores         = 2
  memory_mb         = 4096
  disk_size_gb      = 20
  data_disk_size_gb = 50
  data_disk_path    = "/data"

  # Filter this container's veth. Inert without proxmox_virtual_environment_cluster_firewall below.
  firewall_enabled = true

  # Operator key keeps Ansible/CI able to reach the box; the generated key is the
  # dedicated, shareable one. compact() drops the operator key if it is unset.
  ssh_public_keys = compact([
    trimspace(var.ssh_public_key),
    trimspace(tls_private_key.ssh.public_key_openssh),
  ])

  password = var.host_password
}

# Cluster-wide singleton — Proxmox allows exactly one of these, so it lives in this
# state because nocobase is its only consumer. A second isolated guest must NOT
# redeclare it; hoist it into its own dir instead, or the two states will fight.
#
# Policies are pinned to ACCEPT on purpose: the provider defaults input_policy to
# DROP, which would apply default-deny to the Proxmox node itself. With ACCEPT the
# master switch only activates the machinery — the node and the seven existing
# containers are untouched, since their own firewall flag stays off.
resource "proxmox_virtual_environment_cluster_firewall" "this" {
  enabled       = true
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_options" "nocobase" {
  depends_on = [module.lxc]

  node_name    = local.node_name
  container_id = module.lxc.container_id

  enabled = true

  # Inbound stays open so the LAN can still reach the UI and Ansible can SSH in.
  # Outbound falls through to the rules below; ACCEPT here is what lets the
  # container out to the internet once the LAN destinations are dropped.
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"

  log_level_out = "info"
}

# Evaluated top-down, first match wins, then output_policy. The two ACCEPTs must
# stay above the DROP. Return traffic for LAN-initiated connections is unaffected:
# the Proxmox firewall is stateful and accepts established/related before these run.
resource "proxmox_virtual_environment_firewall_rules" "nocobase" {
  depends_on = [proxmox_virtual_environment_firewall_options.nocobase]

  node_name    = local.node_name
  container_id = module.lxc.container_id

  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "PostgreSQL on postgres-lxc"
    dest    = "192.168.1.4"
    dport   = "5432"
    proto   = "tcp"
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "Redis on redis-lxc"
    dest    = "192.168.1.6"
    dport   = "6379"
    proto   = "tcp"
  }

  rule {
    type    = "out"
    action  = "DROP"
    comment = "No other LAN access"
    dest    = local.lan_cidr
    log     = "info"
  }
}
