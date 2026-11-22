# 1. Bootstrap Proxmox

Start with [Prerequisites](<0 - Prerequisites.md>). Bootstrap runs on your local computer
and connects to Proxmox over SSH. It does not depend on GitHub Actions or Vault.
Install Ansible and `just` locally. Every guest accepts only the operator key, kept as
`SSH_PRIVATE_KEY` (base64) in the root `.env` and in Vault. Password login is needed only
for the first contact with a freshly installed Proxmox node.

## 1. Set the connection inputs

Ansible component: `ansible/00-bootstrap/01-terraform-access/`.

Copy its `.env.example` to `.env` if the local file is missing, set its mode to `600`,
and edit these values:

| Input | Value |
|-------|-------|
| `TARGET_HOST` | Proxmox node address, currently `192.168.1.50` |
| `TARGET_USER` | Administrative SSH user, normally `root` |
| `TARGET_PASSWORD` | SSH password; only for a node that does not have the operator key yet |
| `SSH_PRIVATE_KEY` | Base64 operator key; set here or export it from the root `.env` |

## 2. Apply Terraform access

From the repository root:

```bash
just --justfile ansible/00-bootstrap/01-terraform-access/Justfile apply --ask-pass
```

Omit `--ask-pass` once the node has the operator key. Append its public half
(`ssh-keygen -y` on the decoded key) to the node's `/root/.ssh/authorized_keys` after this
first run, and every later component logs in by key. Alternatively, enter the component
directory and run its dedicated `just apply` command.

The playbook applies `tasks/role.yml`, `tasks/user.yml`, `tasks/permissions.yml`,
and `tasks/token.yml` in order. Its output prints
`PROXMOX_USERNAME=terraform@pve!terraform` and the newly created token's `value`.
Save that value as `PROXMOX_PASSWORD` for local Terraform. On subsequent runs,
the existing token is retained; Proxmox cannot reveal its secret again.

## 3. Check the result

The playbook must finish without failed tasks. Confirm the output identifies the
Terraform user/token. Keep the newly printed token value for step 3, which provisions
the first container. This step does not create any VMs or LXCs.

## Component structure

Each component has this structure:

```
<component>/
├── .env           # local values, ignored by Git
├── .env.example   # checked-in input template
├── Justfile       # just apply [Ansible arguments]
├── playbook.yml   # one operation
└── README.md      # inputs and prerequisites
```

Terraform access also has a `tasks/` directory to keep its four operations readable.
Each component loads only its own `.env`; the root `.env` is not loaded. Blank
credentials in the examples must be filled locally. Values use shell quoting.

## Later components

Continue with [the LXC template](<2 - LXC template.md>). VM images are prepared in
[Storage and k3s](<5 - Storage and k3s.md>). Optional runner and Proxmox TLS components
are described in [Services and verification](<8 - Services and verification.md>).

[The Ansible folder map](../ansible/README.md) lists execution stages and shared code.
