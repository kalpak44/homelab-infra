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