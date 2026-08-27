locals {
  repository      = "proklinator-app"
  default_branch  = "main"
  agent_workflow  = ".github/workflows/ai-pr-agent.yml"
  review_workflow = ".github/workflows/ai-pr-review.yml"
  issue_workflow  = ".github/workflows/ai-issue-agent.yml"
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

  # Issues are the input side of the agent loop — an issue is what the implementer picks
  # up and what its PR closes. `has_projects` is the retired classic-Projects toggle and
  # is unrelated to a Projects V2 board, which lives on the account, not on the repo.
  has_issues   = true
  has_wiki     = false
  has_projects = true

  # Squash-only keeps the auto-merged bot PRs to one commit each on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github proklinator-app` archives the repo — it never deletes it.
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

# Tells both agents which workflow to dispatch when a PR has no check runs at all.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "publish-frontend.yml"
}

# Who ai-pr-review.yml is allowed to act on. A variable rather than a secret on purpose:
# the reviewer prints it in its skip reason, and a login is not a credential. The gate
# fails closed on an empty value, so the reviewer stays inert until this is set.
resource "github_actions_variable" "pr_review_allowlist" {
  repository    = github_repository.this.name
  variable_name = "PR_REVIEW_ALLOWLIST"
  value         = join(",", var.pr_review_allowlist)
}

# How many times the reviewer may send an agent-authored PR back before the loop stops
# and hands the issue to a human. The two agents will otherwise ping-pong indefinitely:
# each round is a full model run plus a browser QA pass, so an uncapped loop is a bill,
# not a bug. Both workflows read it, and both enforce it independently.
resource "github_actions_variable" "ai_max_review_rounds" {
  repository    = github_repository.this.name
  variable_name = "AI_MAX_REVIEW_ROUNDS"
  value         = tostring(var.ai_max_review_rounds)
}

# --- Cluster deploy trigger ---------------------------------------------------------
# publish-frontend.yml dispatches homelab-infra's gitops-bump-images workflow once the
# image is in GHCR, so a merge to main reaches the cluster without waiting for the daily
# cron. The job's own GITHUB_TOKEN is scoped to this repo and cannot dispatch another
# one, hence a PAT. Same credential homelab-infra already uses — Terraform only copies
# it here, it is not a new secret to rotate.
resource "github_actions_secret" "homelab_dispatch" {
  repository  = github_repository.this.name
  secret_name = "GH_ADMIN_TOKEN"
  value       = var.github_token
}

# --- The agents themselves ----------------------------------------------------------
# Two, with a clean split of ownership. ai-pr-agent sweeps bot dependency PRs daily and
# may push compatibility fixes to them. ai-pr-review reacts to a pull_request_target from
# an allowlisted human, never writes to their branch, and merges only behind a merge gate
# the workflow computes in bash. Each one refuses PRs belonging to the other, so they can
# never fight over the same branch.

resource "github_repository_file" "agent_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.agent_workflow
  content             = file("${path.module}/workflows/ai-pr-agent.yml")
  commit_message      = "chore: sync AI PR agent workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
}

resource "github_repository_file" "review_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.review_workflow
  content             = file("${path.module}/workflows/ai-pr-review.yml")
  commit_message      = "chore: sync AI PR review workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
}

resource "github_repository_file" "issue_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.issue_workflow
  content             = file("${path.module}/workflows/ai-issue-agent.yml")
  commit_message      = "chore: sync AI issue agent workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
}