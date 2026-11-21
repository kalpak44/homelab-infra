# 9. Autonomous maintenance agents

Both agents run on the homelab's self-hosted GitHub runner once per day and support
manual dispatch. There is no human-review approval stage for supported migrations.

| Workflow | Daily UTC time | Responsibility |
|----------|----------------|----------------|
| AI Update Agent | 06:00 | Infrastructure health, security updates, host/configuration migrations |
| AI Security Agent | 22:00 | Traffic-based CrowdSec defenses and CrowdSec version/configuration migrations |

Both share a concurrency group. The AI decides what needs updating from security exposure,
upstream fixes, compatibility and actual health. It targets the newest stable version,
including majors, and performs required intermediate migrations. Brief service downtime
during major upgrades is permitted; it must be planned and verified afterward.

## How a run works

1. Collect actual cluster/host versions, health, package availability, traffic and releases.
2. Fetch primary upstream migration documentation requested by the AI.
3. Produce the next coherent migration stage, with evidence, checks and recovery steps.
4. Validate source, render Helm charts, and syntax-check host playbooks.
5. Obtain guest/NFS recovery snapshots before changing services. Stateful roles must add
   application-consistent backup and data-migration steps where filesystem snapshots alone
   are insufficient. Relevant LXC services may be briefly stopped for a major-upgrade checkpoint.
6. Commit and publish validated source, then perform the approved controller operation.
7. Check Flux revision, Helm generation/readiness and CrowdSec rollouts where applicable.
8. Recollect actual health/version evidence. Repair the failed stage before migrating
   dependents, or continue until the assessment and required migrations are complete.

The loop has a 150-minute working window and stops after three consecutive failed repair
attempts. Failure is reported honestly; the controller does not invent success or wait for
an approval. After successful verification, the latest three AI-created snapshots per affected guest
are retained; unrelated/operator snapshots are never pruned. Failed stages keep their checkpoints. It does not blindly downgrade stateful
binaries or restore shared NFS data after newer writes.

## Credentials and prerequisites

Required Actions secrets are `GH_ADMIN_TOKEN`, `DEEPSEEK_APIKEY`, `HOST_PASSWORD`,
`VAULT_USERNAME` and `VAULT_PASSWORD`. These same five also cover the remaining utility
workflows. Deployment credentials are read from the Vault operator archive only when
needed; Proxmox, R2, Cloudflare and service credentials are not copied back into Actions.
The model subprocess does not receive those deployment credentials.

The runner needs Python 3 with PyYAML, Git, npm, curl, kubectl, sshpass, just, Terraform
and Ansible. Workflows install current stable Helm with checksum verification and a pinned
Codex CLI in temporary directories. The existing restricted agent ServiceAccounts/RBAC
in the CrowdSec manifests must be reconciled before running. Agent cluster tokens remain
read-only; fixed controller operations use Vault-backed deployment access separately.

Optional repository variables are `DEEPSEEK_MODEL`, `K3S_SERVER`, `PROMETHEUS_URL`, and
`PROXMOX_SSH_HOST`. Defaults use this repository's current LAN addresses and model settings.
The runner must reach Vault, Proxmox, guest hosts, k3s, Prometheus and upstream sources.

## Controller capabilities and boundaries

The AI proposes structured plans; it cannot send an arbitrary shell command to the controller.
Supported update operations are:

- `configure`: apply a named service's Ansible configuration/migration.
- `os-update`: update one supported guest inventory host using the maintenance playbook.
- `terraform`: initialize, create a saved plan, reject deletion/replacement, and apply that exact plan.
- `packer`: rebuild the supported workspace VM image.
- `scanners`: refresh scanner pins/checksums and managed-repository configuration.

Resource schema, chart values, roles, templates and migration tasks may change when justified
by upstream guidance. A committed source pin without its matching deployment is not completion.
Terraform backends/authentication, operator-secret helpers, agent permissions/validators,
credential files and unrelated application source remain protected. Hypervisor/controller
reboots are not performed out from under the running workflow.

The security agent owns CrowdSec. It can migrate compatible chart/configuration schema and
improve defenses based on actual traffic. Trusted and Cloudflare proxy sources are protected;
there is no numerical ban quota. Ambiguous sources are watched rather than guessed hostile.
Cloudflare edge rules are outside this agent's CrowdSec ownership. Application-owned image
versions remain managed by their separate publish/image-bump workflows.

## Prompts, reports and dry runs

The common contract is `.github/agent-prompts/maintenance-contract.md`; each agent adds its
own scope and decision process. Traffic, release notes and all external content are treated
as untrusted evidence. The controller validates proposals independently of the prompts.

Read the job summary for research, security rationale, each stage, expected/actual downtime,
checkpoint names, deployment results, verification and unresolved gaps. Sanitized command
failures return to the planner; raw credentials and sensitive deployment output do not.

Use manual dispatch with `dry_run=true` to research and validate the next executable stage
without publishing source changes or performing service upgrades/checkpoints. Host collection
may refresh package indexes, but it does not install packages. Normal scheduled runs execute
supported migrations automatically.

## Remove unused Actions secrets

```bash
python3 .github/scripts/audit_secrets.py
python3 .github/scripts/audit_secrets.py --delete-unused
```

Cleanup checks published and local workflow/action consumers, prints names only, and deletes
only unused secrets with recovery copies present in Vault. Credentials without an archive
copy remain for review; the daily bots do not destroy their last recoverable copy.
