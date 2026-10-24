locals {
  repository       = "song-radar"
  default_branch   = "main"
  agent_workflow   = ".github/workflows/ai-maintenance-agent.yml"
  agent_prompt     = ".github/agent-prompts/ai-maintenance-agent.md"
  publish_workflow = ".github/workflows/publish.yml"
  dependabot_file  = ".github/dependabot.yml"
}

# No import block: this repo is created here, unlike the adopted ones under
# terraform/github/. Once it exists the create is a no-op and apply stays idempotent.
resource "github_repository" "this" {
  name       = local.repository
  visibility = "public"

  description = "Self-hosted music discovery from IPTV and radio streams. Automatically identify songs, find available audio, and manage your personal music library."
  topics = [
    "java",
    "spring-boot",
    "thymeleaf",
    "postgresql",
    "iptv",
    "m3u",
    "music-recognition",
    "music-discovery",
    "audio-streaming",
    "self-hosted",
    "music-library",
    "automation",
  ]

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
  gitignore_template = "Java"

  # `just destroy github song-radar` archives the repo — it never deletes it.
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
# publish.yml is the repo's single pipeline — `pull_request`, push to main, and
# `workflow_dispatch`: fmt:check, mvn verify, then SonarCloud with the quality gate
# waited on. It only publishes an image when the ref is main, so the agent can safely
# dispatch it on a dependency PR branch.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "publish.yml"
}

# --- SonarCloud ---------------------------------------------------------------------
# publish.yml's analysis step waits on the quality gate, and the agent's second phase
# reads that gate and the open issues from the SonarCloud API.
#
# `count` guards the value rather than the resource: an apply from a shell with no
# SONAR_TOKEN would otherwise overwrite the stored secret with an empty string, and
# publish.yml's `if: env.SONAR_TOKEN != ''` guard would then skip the analysis while the
# check still went green — a gate that is not gating looks exactly like one that passed.
# terraform/Justfile refuses the apply instead; these keep the stored value safe if it
# is ever run another way.
resource "github_actions_secret" "sonar" {
  count = var.sonar_token != "" ? 1 : 0

  repository  = github_repository.this.name
  secret_name = "SONAR_TOKEN"
  value       = var.sonar_token
}

# GitHub withholds Actions secrets from Dependabot-triggered runs, so without this copy
# the gate is skipped on exactly the pull requests the agent exists to merge.
resource "github_dependabot_secret" "sonar" {
  count = var.sonar_token != "" ? 1 : 0

  repository  = github_repository.this.name
  secret_name = "SONAR_TOKEN"
  value       = var.sonar_token
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

# --- The agent's push credential ----------------------------------------------------
# ai-maintenance-agent.yml authenticates `gh` with this: a merge pushed with the job's
# own GITHUB_TOKEN starts no push-triggered run, so the merged commit would never build
# an image. Same credential homelab-infra already uses — Terraform only copies it here,
# it is not a new secret to rotate.
resource "github_actions_secret" "gh_admin_token" {
  repository  = github_repository.this.name
  secret_name = "GH_ADMIN_TOKEN"
  value       = var.github_token
}

# --- The workflows ------------------------------------------------------------------
# Every workflow this repo has is generated from `workflows/` in this dir, so it is the
# only place either one is edited. A copy hand-edited in the target repo is overwritten
# on the next apply.
#
# A content change here pushes a commit with the PAT, and a PAT push does start
# workflows — so editing publish.yml runs a full build, publish and scan. That is
# intended, and it is also why these files are only rewritten when they really change.

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

  # The prompt is what this workflow runs; a scheduled run that lands between the
  # two files would start the agent with nothing to execute.
  depends_on = [github_repository_file.agent_prompt]
}

resource "github_repository_file" "publish_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.publish_workflow
  content             = file("${path.module}/workflows/publish.yml")
  commit_message      = "chore: sync build workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  # Pushing this file starts a run of it, and its analysis step reads SONAR_TOKEN.
  # Without this, Terraform is free to push the workflow before the secret exists and the
  # first run silently skips the gate.
  depends_on = [github_actions_secret.sonar]
}

# Dependabot is the agent's input side — no dependency PRs, nothing for
# ai-maintenance-agent.yml to sweep. It lives beside `workflows/` here because it lands
# beside them in the target repo: `workflows/` maps to .github/workflows/, this maps to
# .github/dependabot.yml.
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
