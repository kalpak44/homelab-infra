# 6. Initialize Vault and store secrets

Ansible stage: `03-vault/vault-lxc`.

The Vault LXC must exist, its DNS must resolve, and both k3s nodes must be ready.
The current Vault role configures Kubernetes authentication as part of installation.

## 1. Set the initial operator inputs

In the ignored root `.env`, set `HOST_PASSWORD`, `VAULT_USERNAME`, `VAULT_PASSWORD`,
`CLOUDFLARE_API_TOKEN`, and `LETSENCRYPT_EMAIL`. The Vault username and password create
its initial operator login. Use `VAULT_ADDR=https://vault.internal.pavel-usanli.online:8200`
for the local secret helper and Vault CLI.

## 2. Apply the Vault role

From the repository root:

```bash
just --justfile ansible/Justfile configure vault-lxc
curl --fail --silent --show-error \
  https://vault.internal.pavel-usanli.online:8200/v1/sys/health
```

The role installs Vault, configures TLS and its service, initializes and unseals it,
enables KV-v2 at `secret/`, creates the operator login, and connects Kubernetes
authentication to k3s. A successful health response reports `initialized: true`
and `sealed: false`.

Initialization material is currently kept at `/root/vault-init.json` on the Vault
host. Retain a protected copy before relying on this instance for other credentials.

## 3. Archive operator inputs in Vault

```bash
just --justfile ansible/Justfile secrets-store
just --justfile ansible/Justfile secrets-check
```

`secrets-store` archives the root `.env` under `secret/homelab-infra-secrets` and
refuses to overwrite differing stored values. `secrets-check` checks credentials
needed by the remaining GitHub workflows; it is not a full service-secret audit.
These helpers do not yet import the per-component bootstrap environments.

## 4. Prepare service and workload records

Use the Vault UI or a locally installed Vault CLI to sign in. With the CLI, load the
local environment first; userpass login prompts for the password:

```bash
source .env
vault login -method=userpass username="$VAULT_USERNAME"
vault secrets list
```

Follow the exact record names and property tables under
[required secrets in Vault](../gitops/README.md#required-secrets-in-vault). Prepare
records for the workloads enabled in the GitOps manifests, including CrowdSec and
any application integrations you intend to run. Existing generated values should
be read and reused when rebuilding services.

Service roles that use `ansible/shared/tasks/vault-secret.yml` already read their
credentials from Vault. Terraform and the new bootstrap components still use local
environments; converting those to Vault reads is a separate implementation step.

Next: [Install Flux and reconcile workloads](<7 - Flux and workloads.md>).
