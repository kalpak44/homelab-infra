locals {
  repository       = "mite-assistant-mcp"
  default_branch   = "main"
  agent_workflow   = ".github/workflows/ai-pr-agent.yml"
  publish_workflow = ".github/workflows/publish.yml"
  dependabot_file  = ".github/dependabot.yml"
}

# The repo already exists — adopt it instead of creating it. The import block is a no-op
# once the resource is in state, so `terraform apply` stays idempotent from a cold start.
import {
  to = github_repository.this
  id = local.repository
}

resource "github_repository" "this" {
  name       = local.repository
  visibility = "public"

  # Kept as-is on the live repo — listed explicitly so Terraform doesn't blank them.
  description = "mite-assistant-mcp is an MCP server for Mite time tracking that enables AI assistants to read, analyze, and manage time entries through natural language. It provides tools for reporting, reviewing daily and weekly bookings, and creating or updating time entries via the Mite API."

  has_issues   = true
  has_wiki     = true
  has_projects = true

  # Squash-only keeps the auto-merged bot PRs to one commit each on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github mite-assistant-mcp` archives the repo — it never deletes it.
  archive_on_destroy = true
}

# --- DeepSeek credentials -----------------------------------------------------------
# Two stores, deliberately. Workflow runs triggered by a Dependabot PR read from the
# Dependabot secret store, not the Actions one — the same key has to live in both or
# the agent gets an empty DEEPSEEK_APIKEY on exactly the PRs it is meant to handle.

resource "github_actions_secret" "deepseek" {
  repository  = github_repository.this.name
  secret_name = "DEEPSEEK_APIKEY"
  value       = var.deepseek_api_key
}

resource "github_dependabot_secret" "deepseek" {
  repository  = github_repository.this.name
  secret_name = "DEEPSEEK_APIKEY"
  value       = var.deepseek_api_key
}

resource "github_actions_variable" "deepseek_model" {
  repository    = github_repository.this.name
  variable_name = "DEEPSEEK_MODEL"
  value         = var.deepseek_model
}

# Tells the agent which workflow to dispatch when a PR has no check runs at all, and
# which one to dispatch on main once its batch is merged. publish.yml is the repo's single
# pipeline — `pull_request`, push to main, and `workflow_dispatch`: npm ci, format:check,
# lint, then SonarCloud with the quality gate waited on. It publishes an image only when
# the ref is main, so the agent can dispatch it on a dependency PR branch safely.
#
# One variable for both uses on purpose: the merge gate and the publisher are the same
# file, and a second variable naming it would be a second thing that can drift.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "publish.yml"
}

# --- SonarCloud ---------------------------------------------------------------------
# publish.yml's analysis step waits on the quality gate, so a failing gate fails the check
# the agent refuses to merge without. The step is guarded on `SONAR_TOKEN != '' &&
# SONAR_PROJECT_KEY != ''` rather than on the event, so the repo keeps verifying before the
# SonarCloud project exists — which also means a missing project key silently downgrades
# the gate to nothing. Check the step ran, not just that the check went green.
#
# `count` guards the value rather than the resource: an apply with SONAR_TOKEN unset in the
# environment would otherwise overwrite the stored secret with an empty string and disable
# the gate. Deploying this repo without the variable leaves whatever is there untouched.
resource "github_actions_secret" "sonar" {
  count = var.sonar_token != "" ? 1 : 0

  repository  = github_repository.this.name
  secret_name = "SONAR_TOKEN"
  value       = var.sonar_token
}

# The same key in the second store, for the same reason DEEPSEEK_APIKEY is in both: GitHub
# withholds Actions secrets from Dependabot-triggered runs, so on exactly the PRs the agent
# is meant to merge the guard above sees an empty token and skips the analysis. Measured on
# bunker-party PR #3 — the check went green in 34s with `SonarCloud analysis -> skipped`.
resource "github_dependabot_secret" "sonar" {
  count = var.sonar_token != "" ? 1 : 0

  repository      = github_repository.this.name
  secret_name     = "SONAR_TOKEN"
  plaintext_value = var.sonar_token
}

resource "github_actions_variable" "sonar_project_key" {
  repository    = github_repository.this.name
  variable_name = "SONAR_PROJECT_KEY"
  value         = var.sonar_project_key
}

resource "github_actions_variable" "sonar_organization" {
  repository    = github_repository.this.name
  variable_name = "SONAR_ORGANIZATION"
  value         = var.sonar_organization
}

# --- The agent itself ---------------------------------------------------------------

# --- Cluster deploy trigger ---------------------------------------------------------
# Three consumers, one credential. The agent authenticates `gh` with this, and that is
# what makes its merges reach the cluster at all: GitHub starts no push-triggered run for
# a push made with GITHUB_TOKEN, so every merge this agent made landed on main and stopped
# dead — measured on 2026-09-08: PRs #9, #10, #11, #12 and #13 all merged, and not one of
# their merge commits appears among its publish workflow's push runs. The cluster sat on
# `446772e` while main was at `c8e4846`, five dependency updates behind, since 2026-08-20.
# The agent also dispatches the closing rollout with it, and publish.yml's deploy job
# dispatches homelab-infra's gitops-bump-images — a workflow in another repository, which
# that job's own GITHUB_TOKEN is not scoped to reach.
#
# Same credential homelab-infra already uses — Terraform only copies it here, it is not
# a new secret to rotate.
resource "github_actions_secret" "homelab_dispatch" {
  repository  = github_repository.this.name
  secret_name = "GH_ADMIN_TOKEN"
  value       = var.github_token
}

resource "github_repository_file" "agent_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.agent_workflow
  content             = file("${path.module}/workflows/ai-pr-agent.yml")
  commit_message      = "chore: sync AI PR agent workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  depends_on = [github_actions_secret.homelab_dispatch]
}

resource "github_repository_file" "publish_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.publish_workflow
  content             = file("${path.module}/workflows/publish.yml")
  commit_message      = "chore: sync image publish workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  # Pushing this file starts a run of it, and its deploy job reads GH_ADMIN_TOKEN.
  depends_on = [github_actions_secret.homelab_dispatch]
}


resource "github_repository_file" "dependabot" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.dependabot_file
  content             = file("${path.module}/dependabot.yml")
  commit_message      = "chore: sync dependabot config from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
}

# pr-check.yml was folded into publish.yml on 2026-09-08 — see the note in that file.
# `removed` with `destroy = true` is deliberate: the file must actually go, because two
# workflows both triggering on pull_request would run the same checks twice on every
# dependency PR. PR_CHECK_WORKFLOW above is moved to publish.yml in the same apply, so the
# agent is never left naming a workflow that does not exist.
removed {
  from = github_repository_file.check_workflow

  lifecycle {
    destroy = true
  }
}
