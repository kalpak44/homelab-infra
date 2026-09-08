locals {
  repository      = "bunker-party"
  default_branch  = "main"
  agent_workflow  = ".github/workflows/ai-pr-agent.yml"
  build_workflow  = ".github/workflows/build.yml"
  dependabot_file = ".github/dependabot.yml"
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
  description = "A light, fast browser-based party game inspired by Bunker."

  has_issues   = true
  has_wiki     = true
  has_projects = true

  # Squash-only keeps the auto-merged bot PRs to one commit each on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github bunker-party` archives the repo — it never deletes it.
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
# build.yml is the repo's single pipeline — `pull_request`, push to main, and
# `workflow_dispatch`: fmt:check, mvn verify, then SonarCloud with the quality gate
# waited on. It only publishes an image when the ref is main, so the agent can safely
# dispatch it on a dependency PR branch.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "build.yml"
}

# --- SonarCloud ---------------------------------------------------------------------
# The agent's second phase reads the quality gate and open issues from the SonarCloud
# API. SONAR_TOKEN itself belongs to the repo (it predates this layer and is also used
# by build.yml) — only the non-secret coordinates live here.

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

# --- Cluster deploy trigger ---------------------------------------------------------
# Two consumers, one credential. build.yml's deploy job dispatches homelab-infra's
# gitops-bump-images once the image is in GHCR, and the job's own GITHUB_TOKEN is scoped
# to this repo and cannot dispatch another one. ai-pr-agent.yml authenticates `gh` with
# it too, because a merge pushed with GITHUB_TOKEN starts no push-triggered run and so
# would never build the image in the first place. Same credential homelab-infra already
# uses — Terraform only copies it here, it is not a new secret to rotate.
resource "github_actions_secret" "homelab_dispatch" {
  repository  = github_repository.this.name
  secret_name = "GH_ADMIN_TOKEN"
  value       = var.github_token
}

# --- The workflows ------------------------------------------------------------------
# Every workflow this repo has is generated from `workflows/` in this dir, so it is the
# only place either one is edited. A copy hand-edited in the target repo is overwritten
# on the next apply.
#
# build.yml is this repo's CI *and* its deploy trigger, which is why it lives here rather
# than in the repo: the `deploy` job it ends with dispatches homelab-infra's own
# gitops-bump-images workflow, and the app name it passes (`bunker-game-app`) has to
# agree with gitops/Justfile's `apps` list. Splitting the two halves across repos means a
# rename in one silently breaks the other.
#
# A content change here pushes a commit with the PAT, and a PAT push does start workflows
# — so editing build.yml runs a full build, publish and deploy. That is intended, and it
# is also why the file is only rewritten when it really changes.

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

resource "github_repository_file" "build_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.build_workflow
  content             = file("${path.module}/workflows/build.yml")
  commit_message      = "chore: sync build workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  # Pushing this file starts a run of it, and its deploy job reads GH_ADMIN_TOKEN. Without
  # this, Terraform is free to push the workflow before the secret exists and the very
  # first run fails on an empty token — a red run that looks like a workflow bug.
  depends_on = [github_actions_secret.homelab_dispatch]
}

# Dependabot is the agent's input side — no dependency PRs, nothing for ai-pr-agent.yml
# to sweep, which is the state this repo was actually in while Renovate's token sat
# expired. It lives beside `workflows/` here because it lands beside them in the target
# repo: `workflows/` maps to .github/workflows/, this maps to .github/dependabot.yml.
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
