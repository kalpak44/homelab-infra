locals {
  repository       = "mite-assistant-mcp"
  default_branch   = "main"
  agent_workflow   = ".github/workflows/ai-pr-agent.yml"
  publish_workflow = ".github/workflows/publish.yml"
  check_workflow   = ".github/workflows/pr-check.yml"
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

# Tells the agent which workflow to dispatch when a PR has no check runs at all.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "pr-check.yml"
}

# --- The agent itself ---------------------------------------------------------------

# --- Cluster deploy trigger ---------------------------------------------------------
# The agent authenticates `gh` with this, and that is what makes its merges reach the
# cluster. GitHub starts no push-triggered run for a push made with GITHUB_TOKEN, so
# every merge this agent made landed on main and stopped dead — measured on 2026-09-08:
# PRs #9, #10, #11, #12 and #13 all merged, and not one of their merge commits appears
# among its publish workflow's push runs. The cluster sat on `446772e` while main was at
# `c8e4846`, five dependency updates behind, since 2026-08-20.
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

resource "github_repository_file" "check_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.check_workflow
  content             = file("${path.module}/workflows/pr-check.yml")
  commit_message      = "chore: sync PR check workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
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
