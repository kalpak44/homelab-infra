# homelab-infra

Terraform (state on Cloudflare R2) + Ansible + Flux CD GitOps for a Proxmox homelab. All deploy/destroy runs are
triggered manually from GitHub Actions on a self-hosted runner, or locally via `just` recipes.

## Repository layout

```
homelab-infra/
├── terraform/     # Proxmox LXCs/VMs + Cloudflare records + GitHub repos →  see terraform/README.md
├── ansible/       # Post-provisioning for Proxmox services →  see ansible/README.md
├── gitops/        # Flux CD manifests (k3s workloads)      →  see gitops/README.md
└── .github/workflows/
    ├── cloudflare-deploy.yml    | Cloudflare - Deploy
    ├── cloudflare-destroy.yml   | Cloudflare - Destroy
    ├── proxmox-deploy.yml       | Proxmox    - Deploy
    ├── proxmox-destroy.yml      | Proxmox    - Destroy
    ├── github-deploy.yml        | GitHub     - Deploy
    ├── github-destroy.yml       | GitHub     - Destroy
    └── ansible-configure.yml    | Ansible    - Configure
```

Each Terraform resource has its own directory and its own R2 state file. Every service under `terraform/proxmox/` has a
matching config recipe under `ansible/proxmox/`. Both layers expose a `just` interface (`just deploy`, `just destroy`,
`just configure`) - the same command the workflows run.

Detailed usage lives in the sub-READMEs. This document covers **one-time setup** and the **service catalog**.

---

## Setup

### 1. Cloudflare R2 – create bucket and API token

1. Cloudflare dashboard → **R2** → **Create bucket** (e.g. `homelab-terraform-state`)
2. **R2 → Manage R2 API Tokens → Create Account API Token**
    - Permissions: **Object Read & Write**
    - Scope: the bucket you just created
3. Save the shown credentials:

   | Shown on screen       | Save as                |
   |-----------------------|------------------------|
   | **Access Key ID**     | `R2_ACCESS_KEY_ID`     |
   | **Secret Access Key** | `R2_SECRET_ACCESS_KEY` |

4. Copy the **S3 API** URL from the token page (`https://<account-id>.r2.cloudflarestorage.com`) → save as
   `R2_ENDPOINT`.

### 2. Proxmox – initial node setup

All Proxmox setup is automated by the bootstrap playbook. From `ansible/`, set the required env vars and run:

```bash
# SSH key auth (Proxmox node already has your key)
just bootstrap 192.168.1.50

# Fresh node with no keys yet – prompts for the root password once
just bootstrap-pw 192.168.1.50
```

This runs four phases in order (all idempotent – safe to re-run):

| Phase                          | What it does                                                                                                                                        |
|--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 – `01-proxmox-setup.yml`     | Create Terraform role + user + API token; enable snippet storage on `local`                                                                         |
| 2 – `02-proxmox-artifacts.yml` | Download Ubuntu 24.04 LXC template and patch it for SSH password auth; create VM vendor-data snippet; download cloud image; create VM 9000 template |
| 3 – `03-runner-vm.yml`         | Create runner VM 101 with password auth; install ansible/terraform/just/gh; auto-register the GitHub Actions runner                                 |
| 4 – `04-proxmox-tls.yml`       | Register Let's Encrypt ACME account via Cloudflare DNS-01; order cert for the Proxmox web UI                                                        |

The Terraform API token is printed once at the end of phase 1 — **save it immediately** as `PROXMOX_PASSWORD`.
See [`ansible/bootstrap/README.md`](ansible/bootstrap/README.md) for required env vars and per-phase details.

### 3. GitHub – repository secrets

**Settings → Secrets and variables → Actions → New repository secret**:

| Secret                                                               | Where to get it                                                                                              |
|----------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| `R2_ENDPOINT`                                                        | R2 S3 API URL, e.g. `https://<id>.r2.cloudflarestorage.com`                                                  |
| `R2_BUCKET_NAME`                                                     | Bucket name you created                                                                                      |
| `R2_ACCESS_KEY_ID`                                                   | From R2 token page                                                                                           |
| `R2_SECRET_ACCESS_KEY`                                               | From R2 token page                                                                                           |
| `PROXMOX_ENDPOINT`                                                   | `https://<proxmox-ip>:8006`                                                                                  |
| `PROXMOX_USERNAME`                                                   | `terraform@pve!terraform`                                                                                    |
| `PROXMOX_PASSWORD`                                                   | Proxmox API token secret from bootstrap phase 1                                                              |
| `HOST_PASSWORD`                                                      | Root password for every LXC/VM (SSH + console). Bootstrap bakes it in; Ansible keeps it in sync.             |
| `CLOUDFLARE_API_TOKEN`                                               | Cloudflare token with `Zone:DNS:Edit` + email routing perms (see below)                                      |
| `LETSENCRYPT_EMAIL`                                                  | Email for Let's Encrypt registration                                                                         |
| `GITHUB_TOKEN`                                                       | PAT with `repo` scope – bootstrap auto-registers the runner (optional; skipped if unset)                     |
| `GITHUB_REPO`                                                        | `owner/repo` slug for runner registration, e.g. `pnueli/homelab-infra` (required when `GITHUB_TOKEN` is set) |
| `ADGUARD_USERNAME`, `ADGUARD_PASSWORD`                               | AdGuard admin creds                                                                                          |
| `VAULT_USERNAME`, `VAULT_PASSWORD`                                   | Vault admin creds (alphanumeric)                                                                             |
| `POSTGRESQL_DB`, `POSTGRESQL_USER`, `POSTGRESQL_PASSWORD`            | Postgres bootstrap creds                                                                                     |
| `PGADMIN_EMAIL`, `PGADMIN_PASSWORD`                                  | pgAdmin admin creds                                                                                          |
| `REDIS_PASSWORD`, `REDIS_COMMANDER_USER`, `REDIS_COMMANDER_PASSWORD` | Redis + Commander UI creds                                                                                   |
| `RABBITMQ_USER`, `RABBITMQ_PASSWORD`                                 | RabbitMQ admin creds                                                                                         |
| `FLUX_GITHUB_TOKEN`                                                  | GitHub PAT with `repo` scope – Flux CD bootstrap                                                             |
| `CLOUDFLARE_TUNNEL_TOKEN`                                            | Token from `terraform output -raw tunnel_token` after deploying `cloudflare/shared/zero-trust`               |
| `GH_ADMIN_TOKEN`                                                     | PAT used by the `github/` Terraform layer – see [Managed GitHub repos](#managed-github-repos)                |
| `GH_OWNER`                                                           | GitHub user/org owning the managed repos, e.g. `kalpak44` (optional; defaults to `kalpak44`)                 |
| `DEEPSEEK_APIKEY`                                                    | DeepSeek API key – published to each managed repo for the AI PR agent                                        |

### 4. Cloudflare API token - required scopes

The single `CLOUDFLARE_API_TOKEN` needs:

| Type    | Resource                | Permission  |
|---------|-------------------------|-------------|
| Zone    | DNS                     | Edit        |
| Account | Cloudflare Tunnel       | Edit        |
| Account | Zero Trust              | Edit        |
| Account | Email Routing Addresses | Edit + Read |
| Zone    | Email Routing Rules     | Edit + Read |
| Zone    | Zone Settings           | Edit + Read |
| Zone    | SSL and Certificates    | Edit        |

Zone resource is scoped to your domain (e.g. `pavel-usanli.online`). Account-level permissions cover the Zero Trust
tunnel (`cloudflare/shared/zero-trust`). **SSL and Certificates** is what the Cloudflare-for-SaaS custom hostnames in
`saas.tf` need; without it every call to that API returns a bare `Authentication error` rather than a permission
message, so a token missing it looks like a broken token.

---

## Services

All services live behind `*.internal.pavel-usanli.online` (LAN only, unproxied) or `*.pavel-usanli.online` (public,
routed through a Cloudflare Zero Trust tunnel — no open WAN ports required). `proklinator.online` is a second public
zone on the same tunnel, managed from the same `cloudflare/shared/zero-trust` dir — registered at GoDaddy, nameservers
delegated to Cloudflare. Deploy order: Terraform (creates the box + DNS record) → Ansible (configures the service).

| Service                    | Where      | IP            | Terraform dir                          | Ansible dir                                 |
|----------------------------|------------|---------------|----------------------------------------|---------------------------------------------|
| AdGuard Home               | LXC        | 192.168.1.2   | `proxmox/adguard-lxc`                  | `proxmox/adguard-lxc`                       |
| Vault                      | LXC        | 192.168.1.3   | `proxmox/vault-lxc`                    | `proxmox/vault-lxc`                         |
| PostgreSQL + pgAdmin       | LXC        | 192.168.1.4   | `proxmox/postgres-lxc`                 | `proxmox/postgres-lxc`                      |
| Redis + Commander          | LXC        | 192.168.1.6   | `proxmox/redis-lxc`                    | `proxmox/redis-lxc`                         |
| Portainer                  | VM         | 192.168.1.7   | `proxmox/portainer-vm`                 | `proxmox/portainer-vm`                      |
| RabbitMQ                   | LXC        | 192.168.1.8   | `proxmox/rabbitmq-lxc`                 | `proxmox/rabbitmq-lxc`                      |
| NocoBase                   | LXC        | 192.168.1.5   | `proxmox/nocobase-lxc`                 | -                                           |
| whisper.cpp                | LXC        | 192.168.1.9   | `proxmox/whisper-lxc`                  | `proxmox/whisper-lxc`                       |
| Cloudflare Tunnel          | LXC        | 192.168.1.10  | `proxmox/cloudflared-lxc`              | `proxmox/cloudflared-lxc`                   |
| NFS server (k3s PVs)       | VM         | 192.168.1.108 | `proxmox/nfs-vm`                       | `proxmox/nfs-vm`                            |
| k3s control plane          | VM         | 192.168.1.110 | `proxmox/k3s-cluster`                  | `proxmox/k3s-cluster` (`cluster-setup.yml`) |
| k3s worker                 | VM         | 192.168.1.111 | `proxmox/k3s-cluster`                  | (same)                                      |
| Flux CD bootstrap          | -          | (on k3s)      | -                                      | `proxmox/k3s-cluster` (`flux-install.yml`)  |
| Cloudflare Zero Trust      | Cloudflare | -             | `cloudflare/shared/zero-trust`         | -                                           |
| Cloudflare email routing   | Cloudflare | -             | `cloudflare/shared/cloudflare-email`   | -                                           |

### Per-service notes

**AdGuard Home** – Point your router's DNS to `192.168.1.2` (or set it per-device). UI at
`https://adguard.internal.pavel-usanli.online`. To bump versions edit
`ansible/proxmox/adguard-lxc/roles/adguard/defaults/main.yml`.

**Vault** - Playbook initializes, unseals, enables userpass auth, and creates the admin. Unseal key and root token are
saved to `/root/vault-init.json` inside the container - **back this file up**. UI at
`https://vault.internal.pavel-usanli.online:8200`. A systemd override
(`/etc/systemd/system/vault.service.d/override.conf`) auto-unseals Vault after every `vault.service` restart
(e.g. the certbot TLS-renewal hook, or a container/host reboot) using the key from `/root/vault-init.json`, so it no
longer needs a manual unsealing via the UI each time.

**PostgreSQL + pgAdmin** - Both roles run in a single `just configure postgres-lxc`. Postgres listens on
`192.168.1.4:5432`; pgAdmin at `https://pgadmin.internal.pavel-usanli.online`. All hosts on `192.168.1.0/24` connect
with password auth (scram-sha-256).

**Redis** – Redis on `192.168.1.6:6379`, Commander UI at `http://redis.internal.pavel-usanli.online:8081`.

**RabbitMQ** – AMQP on `192.168.1.8:5672`. Management UI at `https://rabbitmq.internal.pavel-usanli.online`.

**whisper.cpp** – Builds `whisper.cpp` from source and downloads the `ggml-large-v3-q5_0.bin` model (~1.1GB) on first
`just configure whisper-lxc`; sized at 3GB RAM / 8GB disk to fit the model in memory. HTTP server (OpenAI-compatible
transcription API) on `192.168.1.9:8080`, no DNS hostname. To change the model edit
`ansible/proxmox/whisper-lxc/roles/whisper/defaults/main.yml`.

**NocoBase** – LAN-isolated: the Proxmox firewall drops all outbound traffic to `192.168.0.0/16` on the
container's veth, except PostgreSQL (`192.168.1.4:5432`) and Redis (`192.168.1.6:6379`). Internet access and
inbound LAN access are unaffected. This is the only consumer of the cluster-wide firewall switch, which is
declared in `terraform/proxmox/nocobase-lxc/` with ACCEPT policies — a second isolated guest must not redeclare it.

Terraform generates a dedicated ED25519 keypair on first apply and writes it to the gitignored
`terraform/proxmox/nocobase-lxc/.ssh/`. A CI apply writes those files into the runner's throwaway workspace, so
recover them with `just output proxmox nocobase-lxc ssh_private_key` — the state on R2 is the copy of record.
`just configure nocobase-lxc` then hardens sshd: **port 22022**, key-only, `PermitRootLogin prohibit-password`.
It deliberately skips `_shared/enable-root-ssh.yml`, which would otherwise force `PasswordAuthentication yes` back
on, and it disables `ssh.socket` — Ubuntu 24.04 socket-activates sshd, which makes the `Port` directive a silent
no-op until systemd hands the port back. Root keeps its password for `pct enter 207` from the node as break-glass.

**Portainer** - Docker + nginx + certbot inside the VM. UI at `https://portainer.internal.pavel-usanli.online`. First
visit shows a setup wizard – create the admin there within 5 minutes of the first launch (
`sudo docker restart portainer` to re-open if it times out).

**k3s cluster** - Two-node cluster (control plane + worker). `just configure k3s-cluster` runs the 3-phase bootstrap (
prep nodes → install server on k3s-1 → join k3s-2). Then `just configure k3s-cluster/flux` installs Flux CD, which
reconciles everything under `gitops/clusters/homelab/`.

To use `kubectl` locally on the `192.168.1.0/24` network:

```bash
scp ubuntu@192.168.1.110:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab.yaml
sed -i '' 's/127.0.0.1/192.168.1.110/' ~/.kube/homelab.yaml
export KUBECONFIG=~/.kube/homelab.yaml
kubectl get nodes
```

**Cloudflare Tunnel** – `cloudflared` daemon running on LXC 210 (`192.168.1.10`). Connects outbound to the
Cloudflare Zero Trust network; all public traffic for `*.pavel-usanli.online` routes through the tunnel to Traefik
at `192.168.1.120` — no open WAN ports needed. The tunnel is provisioned by `cloudflare/shared/zero-trust`
(outputs `tunnel_token`); the daemon is installed and configured by `ansible/proxmox/cloudflared-lxc`.
Firewall: outbound restricted to `192.168.1.120` (k3s) + internet only.

To retrieve the tunnel token after deploying `cloudflare/shared/zero-trust`:

```bash
cd terraform && just output cloudflare shared/zero-trust tunnel_token
```

Save the printed value as `CLOUDFLARE_TUNNEL_TOKEN` in your shell (`~/.zshenv`) and as a GitHub Actions secret.
Then configure the daemon:

```bash
cd ansible && just configure cloudflared-lxc
```

**Cloudflare email routing** - `contact@pavel-usanli.online` forwards to your Gmail. First deploy triggers a
verification email from Cloudflare – click the link in the forwarded message to activate.

For sending from `contact@…` via Gmail: **Gmail → Settings → Accounts → Send mail as → Add**, backed by Mailjet SMTP (
`in-v3.mailjet.com:587`, TLS). Gmail sends its own verification email; approve via the forwarded link. Optional DMARC
record:

```
TXT _dmarc.pavel-usanli.online  →  v=DMARC1; p=none; rua=mailto:contact@pavel-usanli.online
```

Start with `p=none` and tighten to `p=quarantine` / `p=reject` after reports confirm all senders pass SPF/DKIM.

---

## In-cluster services (Flux CD)

Not managed by Terraform or Ansible – Flux reconciles these from `gitops/clusters/homelab/`. See [
`gitops/README.md`](gitops/README.md) for the full list.

Highlights:

- **MetalLB** - LoadBalancer IP pool `192.168.1.120–130`
- **Traefik** - ingress at `192.168.1.120`, TLS via Cloudflare DNS-01
- **cert-manager** - issues Let's Encrypt certs
- **External Secrets Operator** - syncs Vault → k8s secrets
- **CrowdSec** - IDS/IPS + AppSec middleware
- **NFS provisioner** - StorageClass `nfs` backed by `192.168.1.108:/srv/nfs/k8s`
- **Trivy Operator** - container CVE / misconfig / SBOM scanning, board via the Trivy plugin in Headlamp

---

## Managed GitHub repos

`terraform/github/<repo>/` manages the settings of a GitHub repository and installs a DeepSeek-backed agent into it -
either the [PR agent](#what-the-agent-does) or, for the container-image repos, the [release agent](#release-agent).
One directory per repo, one R2 state file each (`homelab/github/<repo>.tfstate`) - same per-resource model as the other
layers.

| Repo                          | Terraform dir               | What it manages                                                                    |
|-------------------------------|-----------------------------|-------------------------------------------------------------------------------------|
| `kalpak44/bunker-party`       | `github/bunker-party`       | same, plus a second agent pass that fixes SonarCloud issues behaviour-preservingly; PR check is the repo's own `build.yml`, which also publishes `ghcr.io/kalpak44/bunker-party` |
| `kalpak44/code-viewer-bot`    | `github/code-viewer-bot`    | same as below, but no `pull_request` workflow - agent reviews and comments without merging |
| `kalpak44/kalpak44`           | `github/kalpak44`           | squash-only merges, `DEEPSEEK_APIKEY`, AI PR agent workflow |
| `kalpak44/kubectl-awscli`     | `github/kubectl-awscli`     | repo settings, `DEEPSEEK_APIKEY`, and the **release agent** workflow - not the PR agent |
| `kalpak44/mac-calendar-mcp`   | `github/mac-calendar-mcp`   | same - but the repo has no `pull_request` workflow, so the agent reviews and comments without ever merging |
| `kalpak44/mite-assistant-mcp` | `github/mite-assistant-mcp` | same                                                        |
| `kalpak44/plugin-noco-tools`  | `github/plugin-noco-tools`  | same; PR check is the repo's own `build.yml`                |
| `kalpak44/postgres-awscli`    | `github/postgres-awscli`    | repo settings, `DEEPSEEK_APIKEY`, and the **release agent** workflow - not the PR agent |
| `kalpak44/proklinator-app`    | `github/proklinator-app`    | same; PR check is the repo's own `publish.yml`, which also publishes `ghcr.io/kalpak44/proklinator-app` and dispatches **GitOps - Bump images** to deploy it. Also gets `GH_ADMIN_TOKEN` for that dispatch, plus a closed agent loop: `ai-issue-agent.yml` implements an `ai:ready` issue and opens a PR, `ai-pr-review.yml` browser-tests it and merges or hands it back, capped by `AI_MAX_REVIEW_ROUNDS` |

**CI stays with the repo.** This layer ships the agent and points it at the repo's own check via the
`PR_CHECK_WORKFLOW` variable (`publish-frontend.yml` / `pr-check.yml`) - it does not manage the check itself. A repo
with no `pull_request` workflow will never have a green check, so the agent will never merge anything there.

The two `*-awscli` container-image repos are the exception: their build workflow *is* managed here, because the agent
that bumps the tool versions and the workflow that publishes the resulting image are the same file. See
[Release agent](#release-agent) below.

Deploy: `just deploy github <repo>` (or the **GitHub - Deploy** workflow).

### What the agent does

Terraform pushes `.github/workflows/ai-pr-agent.yml` into the managed repo. It runs **daily at 06:00 UTC** (`schedule`)
or on demand (`workflow_dispatch`) - it is not triggered per pull request.

One job: it installs the [Codex CLI](https://github.com/openai/codex), points it at DeepSeek, and hands it the `gh` CLI
plus a prompt. The agent then walks the open **bot-authored** PRs oldest first and, for each one in turn:

1. reads the diff and decides whether it is a safe dependency bump,
2. updates the branch if it is behind, and dispatches the repo's own `PR_CHECK_WORKFLOW` if the head commit has no
   checks (a PR opened before that workflow existed never gets one retroactively),
3. waits for every check to conclude,
4. merges with `gh pr merge --squash` **only** if all checks succeeded,
5. confirms the merge landed before moving to the next PR,
6. leaves a short comment explaining the decision.

Human-authored PRs are never merged. The merge policy lives in the prompt, not in bash.

**Why sequential.** Dependency PRs almost always touch the same lockfile. `gh pr merge --auto` arms them all at once and
they collide; merging one at a time means each PR rebases onto the previous merge instead of conflicting.

**Why no branch ruleset.** The agent is the gate - it refuses to merge without a green check. A ruleset was tried and
removed: its `pull_request` rule also blocks Terraform from committing the workflow files it manages
(`409 Changes must be made through a pull request`), which needs an admin bypass actor to work around.

**Wire protocol.** DeepSeek serves the OpenAI Responses API at `/v1/responses`, which is the only protocol Codex still
speaks - `wire_api = "chat"` was removed upstream. They talk directly, with no proxy in between.

**Both secret stores.** The key is written to the Actions *and* Dependabot stores. Runs triggered from a Dependabot PR
read from the Dependabot store, so a key present only in the Actions store would be empty on exactly the PRs that
matter.

### Release agent

`kubectl-awscli` and `postgres-awscli` are container-image repos rather than applications, so they get a different
agent. Terraform pushes `.github/workflows/release.yml` into each. It runs **weekly at 05:00 UTC on Mondays**
(`schedule`), on demand (`workflow_dispatch`, with `force_release` and `security_policy` inputs), and on every push to
`main`.

One job, because every step needs the tree the step before it produced, and because nothing reaches the registry until
the whole chain has passed:

```
resolve upstream (AI)  ->  build  ->  smoke  ->  scan  ->  remediate  ->  rescan
                                                                            |
                          publish  <-  commit  <-  version  <-  policy  <---+
```

**Resolve** - skipped on push. Codex + DeepSeek resolves the latest upstream releases (kubectl from
`dl.k8s.io/release/stable.txt`, Alpine from the Docker Hub tag list), edits the pins **in the Dockerfile itself**,
builds the result to prove it works, and prepends a `CHANGELOG.md` entry with a from/to table plus a short prose
paragraph. It writes `## vNEXT` - it does not pick the version number.

**Build, smoke, scan** - the candidate is built for amd64 with `--no-cache` and is **not pushed**. It must first pass
the compatibility contract: every binary the image promises, the real entrypoint, the uid, the TLS trust store, and -
for `postgres-awscli` - the MODE dispatch plus both scripts' refusal to run without their variables. Then syft + grype
scan it.

**Remediate** - see below. **Publish** - only after the policy gate; the multi-arch push reuses the amd64 layers from
the candidate build via the gha cache, so the bytes published are the bytes that were scanned.

**There is no versions file.** The Dockerfile is the source of truth for what goes in the image, and the newest
`## vX.Y.Z` heading in `CHANGELOG.md` is the version that gets tagged and published. Two files, both human-readable,
no third place to drift.

**The agent is not trusted.** Deterministic gates sit between it and the commit, all in bash:

| Gate | Catches |
|------------|---------------------------------------------------------------------------------------------|
| scope      | anything changed outside `Dockerfile` and `CHANGELOG.md`, or a missing `## vNEXT` heading    |
| provenance | a version that does not exist upstream, a package that does not resolve, a pin moving backwards, an exact `=version` apk pin |
| smoke      | a build whose tools, entrypoint, scripts or Python imports no longer work                    |
| policy     | an image measurably more vulnerable than the one already published                           |

The provenance gate is the important one: it re-resolves every pin against the registry and upstream independently of
the agent, so a hallucinated version cannot reach `main` even if the model is confident about it. The prompt says
"never guess"; the gate is what makes that true.

**Why one job and not two.** A push made with `GITHUB_TOKEN` does not trigger another workflow run, so the agent's bump
commit cannot re-fire `on: push`. Everything happens in one run, and one commit carries the whole result.

**The build and scan run every week**, even when no version moved. A quiet week still refreshes the vulnerability
report and the SARIF upload; it just does not publish.

#### Security policy

Critical and High are acted on. A finding is **fixable** when grype knows a fixed version exists; **unfixable** when
there is no upstream fix at all. A third case is reported separately and matters most in practice: a fix exists
upstream but Alpine has not packaged it yet, so nothing the pipeline can do will reach it.

When any Critical/High remains, remediation is attempted. Each attempt is built, smoke-tested and rescanned, and is
kept **only** if Criticals do not rise, Critical+High strictly falls, every smoke check still passes, and no shipped
tool's major version moved. Otherwise it is reverted whole. Levers: move the Alpine tag (newest first), move kubectl to
current stable, drop a genuinely unneeded package - then one AI round that may propose one more minimal change through
the identical gate.

Publication is decided against the image on `:latest`, **rescanned in the same run with the same grype database** so
the comparison reflects the change rather than a week of database growth:

| `security_policy` | Behaviour |
|-------------------|-----------|
| `enforce` (default) | Block if the candidate has more Criticals, or more Critical+High, than the published image. Findings remediation could not reach do **not** block - refusing to publish would pin consumers to an older image with the same CVEs *plus* the ones already fixed. |
| `strict`            | Additionally block while any fixable Critical/High remains. |
| `report-only`       | Never block. Break-glass, for shipping a rebuild while a scanner or feed problem is sorted out. |

What is deliberately **not** done, because it trades a working image for a green scanner: exact `=version` apk pins,
`edge`/`testing` repositories, pip-installing over the Python libraries Alpine's `aws-cli` package owns, and moving the
PostgreSQL client major (`pg_dump` refuses to read a newer server).

`apk upgrade` is **not** a lever and must not be re-added: it was measured on both images and changes nothing, because
the official `alpine:X.Y` tag already carries the newest patch level and `apk add --no-cache` already fetches current
packages.

The base bump is also **not** a blind `+1`. On `kubectl-awscli`, stepping 3.22 → 3.23 raised Criticals from 8 to 10
while 3.22 → 3.24 cut them to 2; a one-step loop would propose the regression, measure it, revert, and repeat for ever.
The search walks candidate tags newest-first, which is safe precisely because each one is built, smoke-tested and
rescanned before it is kept.

#### Versioning

Releases follow SemVer, and the workflow - not the agent - computes the number from what actually changed between the
published image and the candidate:

| Observed change | Level |
|-----------------|-------|
| a shipped tool's **major** moved, an apk package was dropped, or entrypoint/command/user/workdir changed | breaking |
| the Alpine minor moved, or a shipped tool's **minor** moved | feature |
| anything else that changes the image - tool patch levels, package revisions, a security remediation | fix |

Mapped to a component, honouring SemVer's pre-1.0 clause (§4 - anything may change in `0.y.z`):

| | `0.y.z` | `1.y.z` and up |
|---|---|---|
| breaking | minor | major |
| feature | minor | minor |
| fix | patch | patch |

Previous tool versions come from the `io.homelab.tools.*` labels the last release wrote onto `:latest`, so the
comparison is against what was really published. A PostgreSQL client major move therefore lands as a minor bump today
and as a major bump once the image reaches 1.0.0.

**Pinned vs recorded.** Only what can be reliably pinned is pinned: the Alpine tag, and `KUBECTL_VERSION` in
`kubectl-awscli` (dl.k8s.io keeps every release). `aws-cli` and the PostgreSQL client are installed *unversioned* from
the Alpine package repo, because an exact `=version` apk pin breaks the moment Alpine drops that package - and
`postgresql-client` without a number resolves to whichever major the release ships. Their versions are read back out of
the built image and recorded in the labels and release notes instead. Bumping the Alpine tag is what moves them.

### `GH_ADMIN_TOKEN` scopes

The built-in `GITHUB_TOKEN` cannot manage other repositories, so this layer needs its own PAT:

| PAT type    | Required                                                                              |
|-------------|---------------------------------------------------------------------------------------|
| Classic     | `repo` + `workflow`                                                                   |
| Fine-grained | Administration, Contents, Secrets, Dependabot secrets, Variables, Workflows - all *write* |

> `terraform destroy` on this layer removes the secrets, the agent workflow file and any ruleset. The repository itself
> is **archived, not deleted** (`archive_on_destroy = true`).

---

## CI

Seven workflows, all `workflow_dispatch` (manual), all running on the self-hosted runner:

| Workflow                 | Picks                           | Runs                                 |
|--------------------------|---------------------------------|--------------------------------------|
| `cloudflare-deploy.yml`  | 15 cloudflare/ dirs             | `just deploy cloudflare <resource>`  |
| `cloudflare-destroy.yml` | 15 cloudflare/ dirs             | `just destroy cloudflare <resource>` |
| `proxmox-deploy.yml`     | 9 proxmox/ services             | `just deploy proxmox <resource>`     |
| `proxmox-destroy.yml`    | 9 proxmox/ services             | `just destroy proxmox <resource>`    |
| `github-deploy.yml`      | 5 github/ repos                 | `just deploy github <resource>`      |
| `github-destroy.yml`     | 5 github/ repos                 | `just destroy github <resource>`     |
| `ansible-configure.yml`  | 8 services + `k3s-cluster/flux` | `just configure <resource>`          |
| `gitops-bump-images.yml` | daily 07:00 UTC + manual        | `just bump-images` (in `gitops/`)    |

Each workflow is a single `just` command - all logic lives in the Justfiles under `terraform/` and `ansible/`. See [
`terraform/README.md`](terraform/README.md) and [`ansible/README.md`](ansible/README.md).

## Local development

Same commands the workflows run:

```bash
cd terraform && just list                              # every deployable
cd terraform && just deploy proxmox adguard-lxc        # provision the LXC
cd ansible   && just configure adguard-lxc             # then configure it
cd terraform && just destroy proxmox adguard-lxc       # tear down
```

Locally you need the same env vars listed in the workflow files (`~/.zshrc` or `~/.zshenv` works).

## Security

Never commit secrets - all credentials flow in as env vars (`TF_VAR_*`, Ansible `-e`) or through Vault → External
Secrets Operator. To report a vulnerability, see [`SECURITY.md`](SECURITY.md).

## License

MIT - free to use, copy, modify and redistribute, for any purpose, including commercially. The only condition is the
standard MIT one: keep the license text and copyright notice with any copy or substantial portion. See
[`LICENSE`](LICENSE).