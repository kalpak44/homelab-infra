# 9. Daily maintenance agents

Both workflows run on the self-hosted GitHub runner inside the homelab, once per day.
Schedules take effect when these files are published to the repository's default branch.
They also support a manual `dry_run` dispatch.

| Workflow | Daily UTC time | Work |
|----------|----------------|------|
| `ai-update-agent.yml` | 06:00 | Check infrastructure health and upstream versions; propose verified source-pin updates |
| `ai-security-agent.yml` | 22:00 | Review the last 24 hours of traffic, improve CrowdSec defenses, and check CrowdSec versions |

Both share a concurrency group so they cannot publish competing changes simultaneously.
UTC times stay fixed through daylight-saving changes. Each scheduled workflow runs once
per day; manual dispatch is an additional operator-triggered run.

## Runner prerequisites

Provision the optional runner using `ansible/80-runner/` if it does not already exist.
It needs Python 3 with PyYAML, kubectl, sshpass, Git and npm. The workflows select Node 22
and install Codex CLI `0.171.0` into a temporary directory for each run.

The existing `security-agent` and `update-agent` ServiceAccounts and RBAC are declared in
`gitops/clusters/homelab/infrastructure/crowdsec/agent-rbac.yaml`. Ensure Flux has applied
them before the first run. The runner must reach the k3s server, LAN hosts, Prometheus,
GitHub, chart indexes, upstream release APIs and the configured model provider.

## Required Actions secrets

| Secret | Use |
|--------|-----|
| `GH_ADMIN_TOKEN` | Read release information, check out source, and publish validated changes |
| `DEEPSEEK_APIKEY` | Model provider authentication |
| `HOST_PASSWORD` | Fixed collector reads host health and mints a short-lived agent token on k3s |
| `VAULT_USERNAME`, `VAULT_PASSWORD` | Existing separate Vault-to-Actions synchronization workflow |

No Proxmox API, R2, Cloudflare, Stripe, Auth0 or service credentials are needed by the
new agents. The model subprocess receives the model key, a read-only checkout and
sanitized evidence; its environment excludes root SSH, GitHub and Vault credentials.
The collector removes its kubeconfig before invoking the model and obtains a fresh
restricted token later if publication needs reconciliation checks.

Optional repository variables are `DEEPSEEK_MODEL`, `K3S_SERVER` and `PROMETHEUS_URL`.
Defaults are `deepseek-v4-flash`, `192.168.1.110`, and
`https://prometheus.internal.pavel-usanli.online:9090` respectively.

## What may be updated automatically

The prompts under `.github/agent-prompts/` explain repository ownership, evidence limits,
compatibility requirements, permitted files and the structured proposal format.
`.github/scripts/infra_agent.py` enforces a separate publication boundary:

- Update agent: verified stable forward versions within the current major in existing
  infrastructure HelmRelease pins and Ansible defaults/group-variable version keys.
- Security agent: evidenced CrowdSec bans, scenarios, AppSec rules/configs, profiles,
  their required wiring, and verified CrowdSec version pins. Trusted and proxy sources
  cannot be banned. There is no numerical ban quota: behavior and evidence determine
  whether each source qualifies. Ambiguous sources are watched and reported.

The controller validates allowed paths/fields, compares proposed versions with collected
upstream releases, checks YAML and kustomizations, runs the CrowdSec validator for security
changes, then commits and pushes. Flux applies GitOps changes. The controller checks the
published revision and updated HelmRelease generation; security runs also check rollouts
and pod readiness. It does not automatically downgrade CrowdSec after a failure.

Terraform, Ansible playbooks, package upgrades, host restarts/reboots, Cloudflare edge
changes, major upgrades and Packer builds remain local operations. Ansible source-pin
updates are committed but not applied to hosts; the daily report lists the local commands.
Cached host package lists and retained traffic logs have freshness/coverage limits,
which the report must state explicitly. Own application images remain managed by the
separate GitOps image-bump workflow.

## Read reports and test a run

In GitHub Actions, select either agent and run it manually with `dry_run=true` first.
Read the job summary for health findings, checked versions, traffic evidence, proposed
changes, deferred local work and gaps. Dry runs validate in a separate checkout and
publish no commits. Failed collection or validation is a failed run, not a clean bill
of health. Reports distinguish model proposals from controller-confirmed publication.

## Clean up unused Actions secrets

From the repository root, audit consumers by secret name:

```bash
python3 .github/scripts/audit_secrets.py
```

The audit checks both published default-branch workflows/actions and the proposed local
ones. It separates secrets unused now from those removable only after old workflows are
removed from GitHub. No secret values are printed.

After publishing workflow changes, run:

```bash
python3 .github/scripts/audit_secrets.py --delete-unused
```

Deletion is limited to secrets unused by both published and local workflows and present
in the Vault operator archive. Names without a Vault backup are retained for review.
The existing secret-sync helper reads current workflow references, so it does not restore
credentials that no current workflow needs.
