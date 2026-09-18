locals {
  repository = "deepaudit"
}

# No import block: this repo is created here, unlike the adopted ones under
# terraform/github/. Once it exists the create is a no-op and apply stays idempotent.
resource "github_repository" "this" {
  name       = local.repository
  visibility = "public"

  description = "Scoped, tool-using DeepSeek audit agent that turns authorized HTTP/TLS checks into reproducible evidence"
  topics      = ["security", "deepseek", "llm-agent", "http", "tls", "python"]

  has_issues   = true
  has_wiki     = false
  has_projects = false

  # Squash-only keeps each merged PR to one commit on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github deepaudit` archives the repo — it never deletes it.
  archive_on_destroy = true
}

# --- DeepSeek credentials -----------------------------------------------------------
# `DEEPSEEK_API_KEY` and not the `DEEPSEEK_APIKEY` the PR-agent repos use: this name is
# the one the CLI and .github/workflows/audit.yml already read, and that workflow is not
# generated here, so the repo's spelling is what the secret has to match.

resource "github_actions_secret" "deepseek" {
  repository  = github_repository.this.name
  secret_name = "DEEPSEEK_API_KEY"
  value       = var.deepseek_api_key
}

# Only the Actions store, unlike the PR-agent repos that mirror the key into the
# Dependabot one. Nothing here runs on a Dependabot-triggered event and reads the key —
# audit.yml is workflow_dispatch and the test workflow needs no key — so a second copy
# would be a credential with no reader.

resource "github_actions_variable" "deepseek_model" {
  repository    = github_repository.this.name
  variable_name = "DEEPSEEK_MODEL"
  value         = var.deepseek_model
}
