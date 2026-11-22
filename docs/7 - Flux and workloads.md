# 7. Install Flux and reconcile workloads

Ansible stage: `04-gitops/flux`.

Start after [Vault secrets](<6 - Vault secrets.md>). k3s, NFS, Vault and the required
secret records must be ready. Public workloads also need the Cloudflare connector
from [Networking](<4 - Networking.md>).

## 1. Review what Flux will install

Read `gitops/clusters/homelab/flux-system/` and [the GitOps service catalog](../gitops/README.md).
Flux reconciles the committed infrastructure and application manifests, so prepare
secrets for every enabled workload before installing it. If an enabled application
needs PostgreSQL, Redis or another backing service, provision and configure that
service using [step 8](<8 - Services and verification.md#1-add-standalone-services>)
before enabling the dependent workload. Check private addresses,
domains, NFS exports and Vault endpoint settings against your environment.

## 2. Set Flux bootstrap inputs

In the ignored root `.env`, set `FLUX_GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN`,
`LETSENCRYPT_EMAIL`, and `SSH_PRIVATE_KEY`. The Flux token needs access to bootstrap
`kalpak44/homelab-infra`; review the owner, repository, branch and path in
`ansible/04-gitops/flux/playbook.yml` if using a different repository.

## 3. Install Flux

From the repository root:

```bash
just --justfile ansible/Justfile configure k3s-cluster/flux
ssh root@192.168.1.110 'flux check'
ssh root@192.168.1.110 'flux get kustomizations -A'
ssh root@192.168.1.110 'k3s kubectl get pods -A'
```

The current Flux installation playbook uninstalls an existing Flux installation
before bootstrapping it. Use this for initial setup; normal manifest updates are
committed to Git and reconciled by Flux.

## 4. Check storage, secrets and ingress

```bash
ssh root@192.168.1.110 'k3s kubectl get storageclasses,persistentvolumes'
ssh root@192.168.1.110 'k3s kubectl get pvc -A'
ssh root@192.168.1.110 'k3s kubectl get clustersecretstores'
ssh root@192.168.1.110 'k3s kubectl get externalsecrets -A'
ssh root@192.168.1.110 'k3s kubectl get certificates -A'
```

Check that PVCs bind, the Vault secret store is ready, external secrets synchronize,
and certificates become ready. If a workload is pending, inspect its events before
reapplying unrelated layers:

```bash
ssh root@192.168.1.110 'k3s kubectl get events -A --sort-by=.lastTimestamp'
```

Next: [Add services and verify the installation](<8 - Services and verification.md>).
