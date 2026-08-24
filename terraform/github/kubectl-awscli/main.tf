locals {
  repository       = "kubectl-awscli"
  default_branch   = "main"
  release_workflow = ".github/workflows/release.yml"
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

  # GHCR shows the source repo's description on the package page — keep it accurate.
  description = "Alpine-based image with kubectl and the AWS CLI, rebuilt monthly against the latest upstream releases."

  has_issues   = true
  has_wiki     = true
  has_projects = true

  # Squash-only keeps each version bump to one commit on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = false
  delete_branch_on_merge = true

  # `just destroy github kubectl-awscli` archives the repo — it never deletes it.
  archive_on_destroy = true
}

# --- DeepSeek credentials -----------------------------------------------------------
# Two stores, deliberately. A workflow run triggered by a Dependabot PR reads from the
# Dependabot secret store, not the Actions one. The release agent runs on cron today,
# but seeding both now means adding the PR agent later needs no second apply.

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

# --- The release workflow -----------------------------------------------------------
# This layer owns the workflow; the repo owns its own content. The agent edits
# versions.env / Dockerfile / CHANGELOG.md inside the repo — none of those are
# managed here, so a bump never fights Terraform.

resource "github_repository_file" "release_workflow" {
  repository          = github_repository.this.name
  branch              = local.default_branch
  file                = local.release_workflow
  content             = file("${path.module}/workflows/release.yml")
  commit_message      = "chore: sync release workflow from homelab-infra"
  commit_author       = "homelab-infra"
  commit_email        = "homelab-infra@users.noreply.github.com"
  overwrite_on_create = true
}