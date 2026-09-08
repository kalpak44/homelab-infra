locals {
  repository       = "kalpak44"
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

  has_issues   = false
  has_wiki     = false
  has_projects = true

  # Squash-only keeps the auto-merged bot PRs to one commit each on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github kalpak44` archives the repo — it never deletes it.
  archive_on_destroy = true
}

# --- Advisory-driven updates --------------------------------------------------------
# A separate mechanism from the scheduled updates in dependabot.yml: these fire when an
# advisory lands rather than waiting for Monday, and they reach transitive dependencies.
# Their PRs are the `npm_and_yarn group` ones, distinct from `*-minor-and-patch`.
#
# Both were already enabled on the live repo; declaring them makes that guaranteed rather
# than incidental. The alerts resource is the prerequisite — with no advisories there is
# nothing to act on — hence the explicit dependency. `vulnerability_alerts` on
# github_repository would also work, but the provider deprecates it in favour of this.

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = true

  depends_on = [github_repository_vulnerability_alerts.this]
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
  value         = "publish.yml"
}

# --- Cluster deploy trigger ---------------------------------------------------------
# publish.yml dispatches homelab-infra's gitops-bump-images workflow once the image is
# in GHCR, so a push to main reaches the cluster without waiting for the daily cron. The
# job's own GITHUB_TOKEN is scoped to this repo and cannot dispatch another one, hence a
# PAT. Same credential homelab-infra already uses — Terraform only copies it here, it is
# not a new secret to rotate.
resource "github_actions_secret" "homelab_dispatch" {
  repository  = github_repository.this.name
  secret_name = "GH_ADMIN_TOKEN"
  value       = var.github_token
}

# --- The workflows ------------------------------------------------------------------
# Both of this repo's workflows are generated from here, so `workflows/` in this dir is
# the only place either one is edited. A copy hand-edited in the target repo is
# overwritten on the next apply.
#
# publish.yml is this repo's CI *and* its deploy trigger, which is why it lives here
# rather than in the repo: the `deploy` job it ends with dispatches this repo's own
# gitops-bump-images workflow, and the app name it passes (`personal-web-page`) has to
# agree with gitops/Justfile's `apps` list. Splitting the two halves across repos means
# a rename in one silently breaks the other.
#
# A content change here pushes a commit with the PAT, and a PAT push does start workflows
# — so editing publish.yml runs a full build, publish and deploy. That is intended, and
# it is also why the file is only rewritten when it really changes.

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

resource "github_repository_file" "publish_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.publish_workflow
  content             = file("${path.module}/workflows/publish.yml")
  commit_message      = "chore: sync frontend publish workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
}

# Dependabot is the agent's input side — no dependency PRs, nothing for ai-pr-agent.yml
# to sweep. It lives beside `workflows/` here because it lands beside them in the target
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
