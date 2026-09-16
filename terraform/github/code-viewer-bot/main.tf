locals {
  repository       = "code-viewer-bot"
  default_branch   = "main"
  agent_workflow   = ".github/workflows/ai-pr-agent.yml"
  release_workflow = ".github/workflows/release.yml"
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
  description = "A joke extension that cannot be used."

  has_issues   = true
  has_wiki     = true
  has_projects = true

  # Squash-only keeps the auto-merged bot PRs to one commit each on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github code-viewer-bot` archives the repo — it never deletes it.
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

# release.yml is the repo's PR check and its publisher in one: it verifies on every pull
# request and releases only for a `v*` tag, so the gate that guards a merge and the
# pipeline that ships can never be two files that drift apart.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "release.yml"
}

# --- SonarCloud ---------------------------------------------------------------------
# release.yml's analysis step waits on the quality gate, so a failing gate fails the check
# the agent refuses to merge without. The agent also reads the gate from the API to learn
# which rule failed, because sonar-scanner exits 3 without naming one. The step is guarded
# on `SONAR_TOKEN != '' && SONAR_PROJECT_KEY != ''`, which means a missing project key
# silently downgrades the gate to nothing. Check the step ran, not that the check passed.
#
# `count` guards the value rather than the resource: an apply with SONAR_TOKEN unset in the
# environment would otherwise overwrite the stored secret with an empty string and disable
# the gate.
resource "github_actions_secret" "sonar" {
  count = var.sonar_token != "" ? 1 : 0

  repository  = github_repository.this.name
  secret_name = "SONAR_TOKEN"
  value       = var.sonar_token
}

# The same key in the second store, for the same reason DEEPSEEK_APIKEY is in both: GitHub
# withholds Actions secrets from Dependabot-triggered runs, so on exactly the PRs the agent
# is meant to merge the guard above would see an empty token and skip the analysis.
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

resource "github_repository_file" "release_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.release_workflow
  content             = file("${path.module}/workflows/release.yml")
  commit_message      = "chore: sync marketplace publish workflow from homelab-infra"
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

