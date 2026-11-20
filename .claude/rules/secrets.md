# Rules – Secrets

**Vault is the source of truth for every infrastructure and service secret.**
Roles using `ansible/shared/tasks/vault-secret.yml` read service credentials at
configure time. Bootstrap/operator inputs live in `secret/homelab-infra-secrets`;
the ignored root `.env` and GitHub Actions secrets hold the copies needed before
Vault is reachable. New service credentials belong in per-service Vault records.
The `external-secrets` policy explicitly denies the bootstrap record; keep that
deny when changing the broader service-secret read policy.

Proxmox access, Cloudflare/R2 recovery and a protected initial `.env` are sufficient
for bootstrap recovery into a fresh Vault. Existing Vault-only secrets need a separate
backup/export or deliberate regeneration. Terraform state stays in R2; Vault data does not. Follow
`docs/1 - Bootstrap.md` for first deployment and recovery order.

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

Local operator credentials and `VAULT_ADDR` live in the gitignored root `.env` (mode
`0600`). Justfiles load it automatically without overriding injected CI variables.
Use the root `.env.example` comment template to distinguish initial bootstrap inputs
from later service/optional inputs. `secrets-restore` preserves these comments when
recreating `.env`. Keep its protected recovery copy outside the host being rebuilt.
For direct Vault commands, source `.env` from the repository root first. The Vault
token is cached in `~/.vault-token`:

```bash
source .env
vault login -method=userpass username="$VAULT_USERNAME"
vault kv list secret/
vault kv get secret/rustfs-secrets
vault kv put secret/<app>-secrets key=value ...     # replaces every key
vault kv patch secret/<app>-secrets key=value       # changes one key
```

Never paste a value into a tracked file, a commit message or a PR. A role or
document that needs to tell a person where a credential is names the Vault path, not the value.
