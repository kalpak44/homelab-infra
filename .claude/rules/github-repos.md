T# Rules – Managed GitHub Repos

`terraform/github/<repo>/` manages a GitHub repository's settings and installs a DeepSeek-backed PR agent into it.
One directory per repo, one R2 state file each — same per-resource model as `cloudflare/` and `proxmox/`.

## Layer layout

```
terraform/github/<repo>/
├── backend.tf              # key = homelab/github/<repo>.tfstate
├── versions.tf             # integrations/github ~> 6.0
├── providers.tf            # provider "github" { owner, token }
├── variables.tf            # github_owner, github_token, deepseek_api_key, deepseek_model, ruleset toggles
├── main.tf                 # import block + repo settings + secrets + workflow file + optional ruleset
└── workflows/
    └── ai-pr-agent.yml     # pushed into the target repo via github_repository_file
```

## What each dir manages

| Resource                       | Purpose                                                              |
|--------------------------------|----------------------------------------------------------------------|
| `github_repository`            | merge settings, `allow_auto_merge`, `delete_branch_on_merge`         |
| `github_actions_secret`        | `DEEPSEEK_APIKEY` for normal workflow runs                           |
| `github_dependabot_secret`     | `DEEPSEEK_APIKEY` for Dependabot-triggered runs (separate store)     |
| `github_actions_variable`      | `DEEPSEEK_MODEL`, `PR_CHECK_WORKFLOW`                                |
| `github_repository_file`       | `.github/workflows/ai-pr-agent.yml` — the agent, and nothing else    |

No `github_repository_ruleset`. One was tried and removed — see the last non-negotiable.

**CI belongs to the repo, not to this layer.** This layer ships the agent and names the repo's check via
`PR_CHECK_WORKFLOW`; it does not own the check itself. `mite-assistant-mcp` had no `pull_request` workflow, so a
`pr-check.yml` was seeded from here and then handed over with a `removed` block using `lifecycle { destroy = false }` —
dropped from state, left in the repo. Use that pattern rather than deleting the resource: a plain delete would remove
the file, and with no green check the agent would stop merging.

**Exception — the container-image repos.** `kubectl-awscli` and `postgres-awscli` get `workflows/release.yml` instead
of `ai-pr-agent.yml`, and that file *is* their CI. It is one workflow, and now one **job**, because every step needs
the working tree the step before it produced and because nothing may reach the registry until the whole chain has
passed: resolve upstream (AI) → build → smoke → scan → remediate → rescan → version → commit → publish. It also has to
be one run because a push made with `GITHUB_TOKEN` does not trigger another workflow run, so the agent's commit would
never fire a push-triggered build. It runs weekly (Mondays 05:00 UTC), on dispatch, and on push. These repos have no
`PR_CHECK_WORKFLOW` and no PR agent.

**The build and the scan run on every trigger, including quiet weeks.** A week where no version moved still rebuilds,
rescans, and refreshes the SARIF; it just does not publish. Do not add an early exit that skips the scan when the agent
found nothing — the vulnerability picture changes without the pins changing, and that is the whole point of a weekly
run.

**No versions file.** The Dockerfile holds the pins; the newest `## vX.Y.Z` heading in `CHANGELOG.md` is the published
version. Do not reintroduce a `versions.env` — it was tried and removed. It only duplicated what the Dockerfile already
states, and gave the agent a second place to write a number that the build would then not actually use.

**The agent does not choose the version number.** It writes the literal `## vNEXT`; the workflow computes the real
number from measured facts (see below) and substitutes it. Do not hand that decision back to the prompt — it was the
one number the agent had no way to verify against anything.

**Versioning is SemVer, computed in bash.** A shipped tool's *major* moving, an apk package being dropped, or an
entrypoint/command/user/workdir change is breaking; the Alpine minor or a tool *minor* moving is a feature; everything
else that changes the image is a fix. Mapped through SemVer's pre-1.0 clause (§4), so at `0.y.z` breaking and feature
both bump the minor, and only past 1.0.0 does breaking bump the major. Previous tool versions come from the
`io.homelab.tools.*` labels on `:latest`, which is why those labels must keep being written.

**Never pin an apk package to an exact version.** `postgresql-client` and `aws-cli` are installed unversioned on
purpose: an `=version` pin breaks the moment Alpine drops that package from its repo, and `postgresql-client` without a
number already resolves to whichever major the release ships (18 on Alpine 3.23 and 3.24). The provenance gate rejects
an `=` in the package list for exactly this reason. Bumping the Alpine tag is what moves these tools.

**`apk upgrade` is a no-op here — do not re-add it.** Measured on both images on 2026-08-24: identical Critical/High
counts with and without it. The official `alpine:X.Y` tag is rebuilt at the newest patch level and `apk add --no-cache`
already fetches current packages. It buys a layer and the appearance of hardening.

**Security remediation may jump more than one Alpine minor; the version agent may not.** Measured on `kubectl-awscli`:
3.22 → 3.23 *raised* Criticals from 8 to 10, while 3.22 → 3.24 cut them to 2. A remediation loop capped at one step
would propose the regression, measure it, revert, and repeat every week for ever. The search therefore walks candidate
tags newest-first, which is safe because every candidate is built, smoke-tested and rescanned before it is kept — the
evidence the one-step rule approximates is produced directly. The version agent keeps its one-step climb; that is about
deliberate, attributable tooling movement, which is a different question.

**The smoke suite is the compatibility contract, and it must have teeth.** It checks every binary the image promises,
the real entrypoint, the uid, the TLS trust store, and for `postgres-awscli` the MODE dispatch plus both scripts'
refusal to run without their variables. It also imports `awscli`, `awscli.botocore`, `jmespath`, `urllib3` and
`cryptography` and compiles the exact JMESPath expression `backup.sh` hands to `aws s3api --query` — that last one is
what stops a remediation from "fixing" the two `py3-jmespath` Criticals by removing the package the retention policy
depends on. Verified to fail on a deliberately broken image; a gate that cannot fail is not a gate.

**The publish policy is explicit and must stay non-deadlocking.** Blocking on every Critical/High would freeze both
images for ever: on the newest Alpine, all the residual findings are either unfixed upstream or fixed upstream but not
packaged by Alpine. So `enforce` blocks only a measured regression against `:latest` — rescanned in the same run with
the same grype database, so database growth is never mistaken for a regression. `strict` and `report-only` exist as
dispatch inputs. Refusing to publish an image whose remaining CVEs cannot be reached would pin consumers to an older
image carrying the same CVEs *plus* the ones already fixed.

**The prompt says "never guess"; the bash gates are what make it true.** Between the agents and the commit: scope (only
`Dockerfile` and `CHANGELOG.md` may change, and a Dockerfile change needs a `## vNEXT`), provenance (every pin
re-resolved against the registry and upstream, no backwards moves, no exact apk pins), smoke (the contract above),
accept-or-revert on every remediation (Criticals must not rise, Critical+High must strictly fall, no tool major may
move), and the publish policy. Everything reaches `main` with no human review, so these must stay in bash — never relax
one into a prompt instruction. Terraform owns the workflow only; it never manages `Dockerfile` or `CHANGELOG.md`, so a
bump never fights it.

**Roll a rejected attempt back with a saved copy, not `git checkout -- Dockerfile`.** The version agent's edits are
uncommitted working-tree changes, so checking out from `HEAD` silently discards the base bump the run just made and
validated. The remediation steps snapshot the Dockerfile to `/tmp/sec/Dockerfile.incumbent` and restore from that.

## Non-negotiables

- **Adopt, never create.** Existing repos come in via an `import` block, not a fresh `github_repository`. The import
  block is a no-op once the resource is in state, so `apply` stays idempotent from a cold start.
- **`archive_on_destroy = true`** on every `github_repository`. `just destroy github <repo>` must never delete a repo.
- **The key goes in both secret stores.** Dependabot-triggered runs read from the Dependabot store, not the Actions
  store. A key in only one of them is empty on exactly the PRs the agent is meant to handle.
- **The agent workflow is generated, not hand-edited.** It lives in `workflows/` here and is overwritten in the target
  repo on every apply. Edits made in the target repo are lost.
- **Bot PRs only.** The agent is instructed to match on `is_bot`, not on the login — `gh pr list` reports Dependabot as
  `app/dependabot`, not `dependabot[bot]`. Human PRs are never merged.
- **The agent is the merge gate, and it merges sequentially.** No `gh pr merge --auto`: auto-merge is asynchronous, so
  arming several dependency PRs at once makes them all fire together and collide on the same lockfile. The agent waits
  for checks, merges one PR, confirms it landed, then starts the next.
- **`PR_CHECK_WORKFLOW` must name a workflow that lives in the target repo and runs on `pull_request`.** The agent
  refuses to merge without a green check, so a repo with no PR CI will simply never merge anything. That workflow also
  needs a `workflow_dispatch` trigger, because the agent starts it for PRs whose head commit has no checks — a PR
  opened before the check existed gets none retroactively.
- **No branch ruleset.** A ruleset's `pull_request` rule also rejects Terraform's own commits to the workflow files it
  manages (`409 Changes must be made through a pull request`), which then needs a `bypass_actors` entry for the admin
  role plus `depends_on` ordering. Not worth it when the agent already gates on CI.
- **Codex talks to DeepSeek directly.** DeepSeek serves the OpenAI Responses API at `/v1/responses`, the only wire
  protocol Codex still supports (`wire_api = "chat"` was removed upstream). Do not reintroduce a translating proxy:
  LiteLLM's Responses→chat bridge drops tool-result messages and DeepSeek rejects the resulting message sequence.

## Env vars

| TF var                    | Env var           | Notes                                                          |
|---------------------------|-------------------|----------------------------------------------------------------|
| `TF_VAR_github_token`     | `GH_ADMIN_TOKEN`  | classic `repo` + `workflow`, or fine-grained with write on Administration / Contents / Secrets / Dependabot secrets / Variables / Workflows |
| `TF_VAR_github_owner`     | `GH_OWNER`        | defaults to `kalpak44`                                         |
| `TF_VAR_deepseek_api_key` | `DEEPSEEK_APIKEY` | already present in the shell locally and as a repo secret in CI |

Secret names cannot start with `GITHUB_` (reserved by GitHub) — hence `GH_ADMIN_TOKEN` / `GH_OWNER`.

## Checklist – managing a new repo

1. `cp -r terraform/github/kalpak44 terraform/github/<repo>`.
2. Edit `backend.tf` (state key `homelab/github/<repo>.tfstate`), and in `main.tf` the `repository` /
   `default_branch` locals and the repo settings so the first plan is a no-op on anything you don't intend to change.
   Check the live settings first: `gh api repos/<owner>/<repo>`.
3. Add `<repo>` to the `options:` list in `.github/workflows/github-{deploy,destroy}.yml`.
4. Add a description line to `terraform/Justfile`'s `list` recipe under the GitHub section.
5. Add a row to the **Managed GitHub repos** table in `README.md`.
6. Apply: `just deploy github <repo>`.