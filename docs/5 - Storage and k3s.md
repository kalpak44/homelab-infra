# 5. Build VM storage and k3s

Start after [Networking](<4 - Networking.md>). Run commands from the repository root.

## 1. Prepare the VM clone source

Edit the `.env` in each component with the same Proxmox address and SSH user, then run:

```bash
just --justfile ansible/00-bootstrap/02-snippet-storage/Justfile apply
just --justfile ansible/00-bootstrap/05-vm-ssh-snippet/Justfile apply
just --justfile ansible/00-bootstrap/06-cloud-image/Justfile apply
just --justfile ansible/00-bootstrap/07-vm-template/Justfile apply
```

Each logs in with `SSH_PRIVATE_KEY` from its `.env` or your shell. The VM snippet makes
new VMs accept only that key for root. The final part creates VM template 9000; the
Terraform VM module uses it as its clone source. Keep storage and image paths consistent
between the component environments and the Terraform modules.

## 2. Build the NFS server

Review the NFS VM's disks in `terraform/proxmox/nfs-vm/` and the data-disk setting in
`ansible/02-platform/nfs-vm/`. The configuration formats that data disk for NFS storage.
With local Terraform and service environment inputs ready, run:

```bash
just --justfile terraform/Justfile deploy proxmox nfs-vm
just --justfile ansible/Justfile configure nfs-vm
ssh root@192.168.1.108 'exportfs -v'
```

Confirm `/srv/nfs/k8s` is exported for the configured cluster clients.

## 3. Build the two k3s nodes

Check `terraform/proxmox/k3s-cluster/`, `ansible/inventories/hosts.yml`, and
`ansible/02-platform/k3s-cluster/group_vars/k3s.yml` before applying:

```bash
just --justfile terraform/Justfile deploy proxmox k3s-cluster
just --justfile ansible/Justfile configure k3s-cluster
ssh root@192.168.1.110 'k3s kubectl get nodes -o wide'
```

Both nodes (`192.168.1.110` and `192.168.1.111`) should be `Ready`. At this stage,
configure only k3s; Flux comes after Vault and its required secret records are ready.

Next: [Initialize Vault and store secrets](<6 - Vault secrets.md>).
