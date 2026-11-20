# 2. Prepare the LXC template

After `01-terraform-access` succeeds, prepare the LXC template. This is the next
application step; Vault needs this archive before Terraform can create its container.
Run the commands below from the repository root.

## 1. Download the Ubuntu LXC template

Edit `ansible/00-bootstrap/03-lxc-template/.env`:

- Set `TARGET_HOST` to the Proxmox node address.
- Set `TARGET_USER` to the administrative SSH user, normally `root`.
- Leave `TARGET_PASSWORD` empty for SSH keys or the password prompt.
- Keep `LXC_TEMPLATE` consistent with the Terraform LXC configuration.

```bash
just --justfile ansible/00-bootstrap/03-lxc-template/Justfile apply --ask-pass
```

Omit `--ask-pass` when SSH keys already work. This downloads the Ubuntu archive onto
Proxmox; it does not create a container.

## 2. Enable SSH in the template

Set the same Proxmox connection and `LXC_TEMPLATE` in
`ansible/00-bootstrap/04-lxc-template-ssh/.env`, then run:

```bash
just --justfile ansible/00-bootstrap/04-lxc-template-ssh/Justfile apply --ask-pass
```

This adds the SSH configuration needed for Ansible to connect to new LXCs.
Both parts can be reapplied; completed downloads and patches are skipped.

## 3. Check the result

Both playbooks must finish without failed tasks. The download creates the archive
under `/var/lib/vz/template/cache/` on Proxmox; the patch adds
`etc/ssh/sshd_config.d/99-password-login.conf` inside it. Reapplying each component
skips the completed download or patch.

Next: [Provision the Vault container](<3 - Vault container.md>).
