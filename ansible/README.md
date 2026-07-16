# Ansible

Post-provisioning configuration for the LXCs and VMs created by `terraform/proxmox/`.

## Layout

```
ansible/
├── ansible.cfg
├── Justfile                       # configure / list recipes
├── inventories/
│   └── hosts.yml                  # single flat inventory
└── proxmox/                       # mirrors terraform/proxmox/
    ├── adguard-lxc/
    │   ├── playbook.yml
    │   └── roles/adguard/
    ├── vault-lxc/
    │   └── ...
    ├── postgres-lxc/
    │   ├── playbook.yml           # runs both roles
    │   └── roles/{postgresql,pgadmin}/
    ├── redis-lxc/, rabbitmq-lxc/, nfs-vm/, portainer-vm/
    └── k3s-cluster/
        ├── cluster-setup.yml      # 3-phase k3s bootstrap
        ├── flux-install.yml       # Flux CD bootstrap on the k3s cluster
        ├── group_vars/k3s.yml     # k3s_version, k3s_server_ip
        └── roles/k3s/
```

Each service dir is self-contained: playbook + colocated `roles/`. Ansible auto-discovers `roles/` next to a playbook,
so no path config is needed.

## Usage

```bash
just configure <resource>       # ansible-playbook against the picked recipe
just list                       # human-readable listing of all resources
```

Examples:

```bash
just configure adguard-lxc
just configure postgres-lxc
just configure k3s-cluster          # the cluster-setup.yml playbook
just configure k3s-cluster/flux     # the flux-install.yml playbook
```

## Environment variables

Every playbook gets **all** the following as `-e` extra vars. Ansible silently drops undeclared ones, so a single flat
list works for every service:

| Var                                                                  | Used by                                                                |
|----------------------------------------------------------------------|------------------------------------------------------------------------|
| `SSH_PRIVATE_KEY`                                                    | CI only - written to `~/.ssh/id_ed25519` by the private `setup` recipe |
| `CLOUDFLARE_API_TOKEN`                                               | certbot DNS-01 (any role with TLS)                                     |
| `LETSENCRYPT_EMAIL`                                                  | certbot registration                                                   |
| `ADGUARD_USERNAME`, `ADGUARD_PASSWORD`                               | adguard-lxc                                                            |
| `VAULT_USERNAME`, `VAULT_PASSWORD`                                   | vault-lxc                                                              |
| `POSTGRESQL_USER`, `POSTGRESQL_PASSWORD`, `POSTGRESQL_DB`            | postgres-lxc (postgresql role)                                         |
| `PGADMIN_EMAIL`, `PGADMIN_PASSWORD`                                  | postgres-lxc (pgadmin role)                                            |
| `REDIS_PASSWORD`, `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD` | redis-lxc                                                              |
| `RABBITMQ_USER`, `RABBITMQ_PASSWORD`                                 | rabbitmq-lxc                                                           |
| `FLUX_GITHUB_TOKEN`                                                  | k3s-cluster/flux                                                       |
