locals {
  repository       = "proklinator-app"
  default_branch   = "main"
  agent_workflow   = ".github/workflows/ai-pr-agent.yml"
  issue_workflow   = ".github/workflows/ai-issue-resolver-agent.yml"
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

# Tells both agents which workflow to dispatch when a pull request has no check runs at
# all, and which one the resolver waits on before it merges. publish.yml is this repo's
# single pipeline — one variable for both uses, because the merge gate and the publisher
# are the same file and a second variable naming it would be a second thing that drifts.
resource "github_actions_variable" "pr_check_workflow" {
  repository    = github_repository.this.name
  variable_name = "PR_CHECK_WORKFLOW"
  value         = "publish.yml"
}

# Who may spend model budget by labelling an issue `ai:ready`. A variable rather than a
# secret on purpose: the resolver prints it in its skip reason, and a login is not a
# credential. The gate fails closed on an empty value, so the loop stays inert until this
# is set.
resource "github_actions_variable" "pr_review_allowlist" {
  repository    = github_repository.this.name
  variable_name = "PR_REVIEW_ALLOWLIST"
  value         = join(",", var.pr_review_allowlist)
}

# How many failed check runs the resolver may try to repair before it stops and hands
# the issue to a human. A change that will not go green would otherwise burn a model run
# and a browser QA pass per attempt, for ever. The plan job enforces it on the way in and
# the land job refuses to dispatch past it, so neither half can run away on its own.
resource "github_actions_variable" "ai_max_fix_rounds" {
  repository    = github_repository.this.name
  variable_name = "AI_MAX_FIX_ROUNDS"
  value         = tostring(var.ai_max_fix_rounds)
}

# AI_MAX_REVIEW_ROUNDS went with ai-pr-review.yml. `destroy = true` so it actually leaves
# the repository: a stale Actions variable reads as configuration nothing consults.
removed {
  from = github_actions_variable.ai_max_review_rounds

  lifecycle {
    destroy = true
  }
}

# --- SonarCloud ---------------------------------------------------------------------
# Two projects, one per package, because the site and the API are separate lockfiles and
# separate images and a gate failure has to be attributable to one of them. Both are
# waited on in publish.yml, so either one failing fails the check the agents refuse to
# merge without.
#
# `count` guards the value rather than the resource: an apply with SONAR_TOKEN unset in
# the environment would otherwise overwrite the stored secret with an empty string, and
# publish.yml's `SONAR_TOKEN != ''` guard would then skip the analysis while the check
# still went green. Deploying this repo without the variable leaves what is there alone.
resource "github_actions_secret" "sonar" {
  count = var.sonar_token != "" ? 1 : 0

  repository  = github_repository.this.name
  secret_name = "SONAR_TOKEN"
  value       = var.sonar_token
}

# The same key in the second store, for the same reason DEEPSEEK_APIKEY is in both:
# GitHub withholds Actions secrets from Dependabot-triggered runs, so on exactly the PRs
# the agent is meant to merge the guard sees an empty token and skips the analysis.
resource "github_dependabot_secret" "sonar" {
  count = var.sonar_token != "" ? 1 : 0

  repository  = github_repository.this.name
  secret_name = "SONAR_TOKEN"
  value       = var.sonar_token
}

resource "github_actions_variable" "sonar_organization" {
  repository    = github_repository.this.name
  variable_name = "SONAR_ORGANIZATION"
  value         = var.sonar_organization
}

resource "github_actions_variable" "sonar_project_key_site" {
  repository    = github_repository.this.name
  variable_name = "SONAR_PROJECT_KEY_SITE"
  value         = var.sonar_project_key_site
}

resource "github_actions_variable" "sonar_project_key_api" {
  repository    = github_repository.this.name
  variable_name = "SONAR_PROJECT_KEY_API"
  value         = var.sonar_project_key_api
}

# --- Cluster deploy trigger ---------------------------------------------------------
# publish.yml dispatches homelab-infra's gitops-bump-images workflow once the
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
# Two, with a clean split of ownership by branch. ai-pr-agent sweeps bot dependency PRs
# daily and may push compatibility fixes to them. ai-issue-resolver-agent implements an
# `ai:ready` issue on an `ai/issue-*` branch and merges it once the check run is green.
# The resolver refuses any branch it did not create and the sweep only ever touches
# bot-authored pull requests, so they cannot fight over one branch.

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

resource "github_repository_file" "issue_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.issue_workflow
  content             = file("${path.module}/workflows/ai-issue-resolver-agent.yml")
  commit_message      = "chore: sync AI issue resolver workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  # It merges with this, and a merge made with GITHUB_TOKEN starts no run on main.
  depends_on = [github_actions_secret.homelab_dispatch]
}

# ai-pr-review.yml is gone and its work is folded into the resolver. `destroy = true` is
# deliberate: the file must actually leave the repository, because it triggers on
# `pull_request_target` and would keep reviewing and merging on its own otherwise.
#
# ai-issue-agent.yml is the resolver's old name. `file` forces replacement, so Terraform
# deletes the old path and writes the new one in the same apply — but only if the old
# resource is removed from state rather than renamed, hence this block.
removed {
  from = github_repository_file.review_workflow

  lifecycle {
    destroy = true
  }
}

# --- The repo's CI, which is also its PR check and its deploy trigger ---------------
# publish.yml lives here rather than in the target repo because it is coupled to this
# layer at three points: PR_CHECK_WORKFLOW above names it, the `deploy` job it ends with
# dispatches homelab-infra's own gitops-bump-images, and the app name it passes
# (`proklinator`) has to agree with gitops/Justfile's `apps` list. It publishes two
# images from one commit, so adding a third means adding it to that list too or its
# Deployment sits on an older tag.
#
# A content change here pushes a commit with the PAT, and a PAT push does start
# workflows — so editing publish.yml runs a full verify, publish and deployment. That is
# intended, and it is also why the file is only rewritten when it really changes.
resource "github_repository_file" "publish_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.publish_workflow
  content             = file("${path.module}/workflows/publish.yml")
  commit_message      = "chore: sync publish workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true

  # Pushing this file starts a run of it, and its deploy job reads GH_ADMIN_TOKEN. On a
  # cold start Terraform is otherwise free to push the workflow before the secret exists,
  # and the first run fails on an empty token — a red run that looks like a workflow bug.
  depends_on = [github_actions_secret.homelab_dispatch]
}

# Dependabot is the agents' input side — no dependency PRs, nothing for ai-pr-agent.yml
# to sweep, which is the state this repo was in: a daily sweep over an empty queue. It
# lives beside `workflows/` here because it lands beside them in the target repo:
# `workflows/` maps to .github/workflows/, this maps to .github/dependabot.yml.
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
