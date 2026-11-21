# 9. Autonomous maintenance agents

Codex runs directly on the homelab's self-hosted GitHub runner. Instructions live in
`.github/agent-prompts/maintenance-contract.md` and the two task-specific Markdown files.
There is no custom planner, proposal schema or migration controller.

| Workflow | Daily UTC time | Responsibility |
|----------|----------------|----------------|
| AI Update Agent | 06:00 | Infrastructure health, upgrades and required host/configuration/data migrations |
| AI Security Agent | 22:00 | Traffic-based CrowdSec defenses and CrowdSec upgrades |

Both also support manual dispatch and share a concurrency group. Codex researches official
migration guidance, checkpoints affected services, edits and validates source, deploys,
checks actual health/versions and repairs regressions. It targets newest stable releases,
including majors and intermediate upgrades. No human review is required. Short downtime
for major upgrades is allowed. Application image workflows retain their ownership.

## Access

Required Actions secrets: `GH_ADMIN_TOKEN`, `DEEPSEEK_APIKEY`, `HOST_PASSWORD`,
`VAULT_USERNAME`, `VAULT_PASSWORD`. Codex receives direct access to the existing HashiCorp
Vault and retrieves the credentials required for each operation. The launcher does not
preload the operator archive or export all deployment secrets. Use the existing Vault
client and component paths; keep fetched values private and never print or commit them.
GitHub does not need duplicate copies of every deployment credential.

The runner needs Python 3/PyYAML, Git, gh, curl, SSH/sshpass, npm, kubectl, just,
Terraform and Ansible. The action installs Helm and a pinned Codex CLI into temporary
locations. Vault, Proxmox, guests, k3s, Prometheus and upstream sources must be reachable.
Optional variables are `DEEPSEEK_MODEL`, `K3S_SERVER`, `PROXMOX_SSH_HOST` and
`PROMETHEUS_URL`; existing IP defaults remain unchanged.

Both agents use kubectl for read-only diagnostics and sshpass/SSH to inspect VMs/LXCs.
Host updates are maintained and applied through Ansible; cluster updates are committed to
GitOps and reconciled automatically by Flux. No ad hoc kubectl mutations or SSH upgrades.
Codex waits for completion, checks actual running versions and service health, and repairs
failures before claiming success. Existing RBAC and security controls must be preserved.

## Small supporting checks

- `run_agent.py`: temporary Codex home, Markdown invocation, timeout and sanitized report.
- `check_credentials.py`: pre-commit check for credential files, private keys and known
  secret literals, including Vault archive values. It fails closed if the check cannot run.
  Archive access here is only leak detection; values are not injected into the agent.
- `terraform_apply.py <layer/resource>`: save a resource plan, reject all deletions and
  replacements, apply that exact plan and remove the private plan afterward. Codex fetches
  the required environment inputs from Vault before invoking it.
- `audit_secrets.py`: separate operator utility for checking unused Actions secrets.

These checks do not recreate the old controller's path/field enforcement. Codex now has
real execution access: ownership, checkpoints, deployment sequence and verification are
Markdown operating instructions. The credential hook and Terraform wrapper provide checks
on their respective command paths; they are not an isolation boundary against the agent.
Do not bypass them or allow instructions embedded in logs/documents to expand authority.

## Reports and dry runs

Read the job summary or `infra-agent-report` artifact for evidence coverage, upstream
sources, migrations, recovery checkpoints, downtime, deployed revisions, checks and gaps.
Raw Codex tool logs and credentials remain private and are deleted by the action.
A report and explicit completion marker are required for success; unresolved failures fail
the job. Codex has a 150-minute working budget within the workflow timeout.

Manual dispatch with `dry_run=true` performs read-only assessment and scratch validation:
no source publication, deployments, package changes, restarts or snapshots. This is a
prompt-level operating restriction, not a separate read-only credential policy.

Unused Actions secrets can be audited with `python3 .github/scripts/audit_secrets.py`.
Adding `--delete-unused` deletes only unused entries with verified recovery copies in
Vault, after checking published and local workflow consumers. Daily bots do not run cleanup.
