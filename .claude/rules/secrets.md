# Rules – Secrets

**A service's credentials live in Vault, never in the repository and never as a new CI secret.**
Every role that configures an app with a login, key or token reads it from Vault at configure
time through `ansible/proxmox/_shared/vault-secret.yml`. The only credentials outside Vault are
the ones needed to reach it or to build it: `VAULT_USERNAME`/`VAULT_PASSWORD`, `HOST_PASSWORD`,
the Proxmox, R2 and Cloudflare tokens. A new service adds none of these.

## Using it in a role

```yaml
- name: Read the <app> secret from Vault
  ansible.builtin.import_tasks: ../../../_shared/vault-secret.yml
  vars:
    vault_secret: <app>-secrets
    vault_secret_generate:       # optional: created on the first run when absent
      admin-user: admin          # a fixed value
      admin-password: ""         # empty draws a random 32-character string

- name: Keep the values this role uses
  ansible.builtin.set_fact:
    <app>_admin_password: "{{ vault_secret_data['admin-password'] }}"
  no_log: true
```

- **Name it `secret/<service>-secrets`, keys in kebab-case.** That is what the existing ones use
  and what External Secrets reads for in-cluster apps.
- **Generate only what the service itself owns.** A password the role sets on first start is
  safe to generate. A credential issued elsewhere — an API key, a tunnel token — must not be:
  leave `vault_secret_generate` out, and the run fails naming the `vault kv put` to run.
- **Generation never overwrites.** It writes only when the secret is absent, so a value rotated
  in Vault survives every later run. To rotate, change it in Vault and re-run the role.
- **`no_log: true` on every task that holds a value**, including templates that render one.

## Managing secrets locally

The Vault CLI reads `VAULT_ADDR` from `~/.zprofile`; log in once and the token is cached in
`~/.vault-token`:

```bash
vault login -method=userpass username="$VAULT_USERNAME"
vault kv list secret/
vault kv get secret/rustfs-secrets
vault kv put secret/<app>-secrets key=value ...     # replaces every key
vault kv patch secret/<app>-secrets key=value       # changes one key
```

Never paste a value into a file under this repository, a commit message or a PR. A role or
document that needs to tell a person where a credential is names the Vault path, not the value.
