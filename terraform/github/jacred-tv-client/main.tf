locals {
  repository       = "jacred-tv-client"
  default_branch   = "main"
  agent_workflow   = ".github/workflows/ai-maintenance-agent.yml"
  agent_prompt     = ".github/agent-prompts/ai-maintenance-agent.md"
  release_workflow = ".github/workflows/release.yml"
  dependabot_file  = ".github/dependabot.yml"
}

# No import block: this repo is created here, unlike the adopted ones under
# terraform/github/. Once it exists the create is a no-op and apply stays idempotent.
resource "github_repository" "this" {
  name       = local.repository
  visibility = "public"

  description = "Android TV client for the jac.red torrent index, with a Matrix server as its backend"
  topics      = ["android-tv", "android", "java", "jacred", "matrix"]

  has_issues   = true
  has_wiki     = false
  has_projects = false

  # Squash-only keeps the auto-merged bot PRs to one commit each on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # Gives the repo a main branch to push the app onto; an uninitialized repo has no
  # default branch at all, so the first clone fails. Both only apply at creation.
  auto_init          = true
  gitignore_template = "Android"

  # `just destroy github jacred-tv-client` archives the repo — it never deletes it.
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

# --- Release signing ----------------------------------------------------------------
# Android only replaces an installed app when the new APK carries the same signature, so
# the key has to outlive any one CI run. release.yml used to generate one per run, which
# meant no release could ever update another. The keystore password and alias are in
# release.yml in the clear on purpose: the file is the credential, and a password stored
# beside it in the same secret store protects nothing.
#
# `count` guards the value rather than the resource: an apply with the variable unset
# would otherwise replace the stored keystore with an empty string, and the next release
# would fail at a signing step nobody was looking at.
resource "github_actions_secret" "android_keystore" {
  count = var.android_keystore_base64 != "" ? 1 : 0

  repository  = github_repository.this.name
  secret_name = "ANDROID_KEYSTORE_BASE64"
  value       = var.android_keystore_base64
}

# The repo's own CI. release.yml runs on pull_request and also has a workflow_dispatch
# trigger, which is what the agent needs to start it on a PR that has no check runs.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "release.yml"
}

# No SonarCloud here, unlike the other repos running this agent: there is no test suite
# to measure and no project to analyse against. The gate is the build plus lint, which
# app/build.gradle sets to abortOnError so it fails the check rather than filing a
# report. The agent's Sonar step reads an empty project key and skips itself.

# --- The agent itself ---------------------------------------------------------------

# The agent authenticates `gh` with this instead of GITHUB_TOKEN, so that a push it makes
# — to a PR branch or to main — actually raises workflow runs. GitHub starts none for a
# GITHUB_TOKEN push, so the tag it cuts would land and nothing would build it. Same
# credential homelab-infra already uses; Terraform only copies it here.
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

resource "github_repository_file" "release_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.release_workflow
  content             = file("${path.module}/workflows/release.yml")
  commit_message      = "chore: sync release workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  depends_on = [github_actions_secret.android_keystore]
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
