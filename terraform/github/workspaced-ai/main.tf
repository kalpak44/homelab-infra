locals {
  repository = "workspaced-ai"
}

# No import block: this repo is created here, unlike the adopted ones under
# terraform/github/. Once it exists the create is a no-op and apply stays idempotent.
resource "github_repository" "this" {
  name       = local.repository
  visibility = "public"

  description = "A platform for running AI agents in isolated, configurable workspaces with real-time streaming and extensible tooling."
  topics      = ["ai-agents", "llm", "workspaces", "streaming", "sandbox"]

  has_issues   = true
  has_wiki     = false
  has_projects = false

  # Squash-only keeps each merged PR to one commit on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github workspaced-ai` archives the repo — it never deletes it.
  archive_on_destroy = true
}
