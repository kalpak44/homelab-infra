locals {
  repository       = "noco-google-connector-web-page"
  default_branch   = "main"
  agent_workflow   = ".github/workflows/ai-maintenance-agent.yml"
  agent_prompt     = ".github/agent-prompts/ai-maintenance-agent.md"
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
  description = "Public web page for the NocoBase Google connector: the privacy policy and terms of service Google OAuth verification requires."

  has_issues   = true
  has_wiki     = true
  has_projects = true

  # Squash-only keeps the auto-merged bot PRs to one commit each on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github noco-google-connector-web-page` archives the repo — it never deletes it.
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

# The repo's own CI. publish.yml runs on pull_request and also has a workflow_dispatch
# trigger, which is what the agent needs to start it on a PR that has no check runs.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "publish.yml"
}

# --- The agent itself ---------------------------------------------------------------

# --- The agent's git credential -----------------------------------------------------
# The agent authenticates `gh` with this instead of GITHUB_TOKEN, so that a push it makes
# — to a PR branch or to main — actually raises workflow runs. GitHub starts none for a
# GITHUB_TOKEN push. Same credential homelab-infra already uses; Terraform only copies it
# here, it is not a new secret to rotate.
resource "github_actions_secret" "homelab_dispatch" {
  repository  = github_repository.this.name
  secret_name = "GH_ADMIN_TOKEN"
  value       = var.github_token
}

# The policy the agent runs on, kept as prose instead of a heredoc inside the workflow:
# a thousand lines of prompt buried in YAML is neither readable nor reviewable. The
# workflow reads it from the checkout, so it has to be in the repo, not only here.
resource "github_repository_file" "agent_prompt" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.agent_prompt
  content             = file("${path.module}/agent-prompts/ai-maintenance-agent.md")
  commit_message      = "chore: sync AI maintenance agent prompt from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
}

resource "github_repository_file" "agent_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.agent_workflow
  content             = file("${path.module}/workflows/ai-maintenance-agent.yml")
  commit_message      = "chore: sync AI maintenance agent workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  depends_on = [github_repository_file.agent_prompt, github_actions_secret.homelab_dispatch]
}

resource "github_repository_file" "publish_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.publish_workflow
  content             = file("${path.module}/workflows/publish.yml")
  commit_message      = "chore: sync publish workflow from homelab-infra"
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
