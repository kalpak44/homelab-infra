# 4. Establish DNS and public ingress

Start after [provisioning the Vault container](<3 - Vault container.md>). Run commands from the
repository root. Ansible DNS configuration lives in `01-networking/adguard-lxc`;
the optional connector lives in `05-services/cloudflared-lxc`. These Terraform and
service recipes load the root `.env`.

## 1. Create internal DNS records

Set `CLOUDFLARE_API_TOKEN` and the R2 backend inputs in `.env`. Review the address map
in `terraform/cloudflare/zones/pavel-usanli.online/internal/main.tf`, then apply it:

```bash
just --justfile terraform/Justfile deploy cloudflare zones/pavel-usanli.online/internal
```

Check the DNS names from your workstation:

```bash
nslookup vault.internal.pavel-usanli.online
nslookup proxmox.internal.pavel-usanli.online
```

They should resolve to the configured private LAN addresses, including `192.168.1.3`
for Vault. Your resolver must allow these private responses.

## 2. Provision and configure AdGuard

Set `SSH_PRIVATE_KEY`, `ADGUARD_USERNAME`, `ADGUARD_PASSWORD`, `LETSENCRYPT_EMAIL` and
`CLOUDFLARE_API_TOKEN` in the local service environment, then run:

```bash
just --justfile terraform/Justfile deploy proxmox adguard-lxc
just --justfile ansible/Justfile configure adguard-lxc
```

Check the resolver before changing your router's DHCP DNS setting:

```bash
nslookup vault.internal.pavel-usanli.online 192.168.1.2
```

When it answers correctly, configure LAN clients to use AdGuard at `192.168.1.2`.

## 3. Set the host resolvers

The Proxmox node and its guests resolve through `1.1.1.1` and `1.0.0.1`, not AdGuard, which
runs on the same node. Set them now, before more containers exist: each LXC copies the
node's resolvers when it starts, and Vault already does.

```bash
just --justfile ansible/Justfile dns proxmox,vault
```

VMs get the same pair from cloud-init. Later, `just --justfile ansible/Justfile dns`
covers every host.

## 4. Prepare public ingress when needed

This can wait until the internal cluster is ready. Review
`terraform/cloudflare/tunnels/homelab/`, then apply it and retrieve the connector token:

```bash
just --justfile terraform/Justfile deploy cloudflare tunnels/homelab
just --justfile terraform/Justfile output cloudflare tunnels/homelab tunnel_token
```

Store the output locally as `CLOUDFLARE_TUNNEL_TOKEN`, then configure the connector:

```bash
just --justfile terraform/Justfile deploy proxmox cloudflared-lxc
just --justfile ansible/Justfile configure cloudflared-lxc
```

A healthy connector does not yet mean an application is deployed. Flux installs the
Traefik configuration and workloads later.

Next: [VM storage and k3s](<5 - Storage and k3s.md>).
