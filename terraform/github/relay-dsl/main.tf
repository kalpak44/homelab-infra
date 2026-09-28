locals {
  repository = "relay-dsl"
}

# No import block: this repo is created here, unlike the adopted ones under
# terraform/github/. Once it exists the create is a no-op and apply stays idempotent.
resource "github_repository" "this" {
  name       = local.repository
  visibility = "public"

  description = "A lightweight workflow DSL with Java and JavaScript interpreters, supporting retries, conditions, and fallbacks."
  topics = [
    "dsl",
    "domain-specific-language",
    "workflow-automation",
    "java",
    "javascript",
    "interpreter",
    "parser",
    "automation",
    "retry",
    "error-handling",
  ]

  has_issues   = true
  has_wiki     = false
  has_projects = false

  # Squash-only keeps each merged PR to one commit on main.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true

  # `just destroy github relay-dsl` archives the repo — it never deletes it.
  archive_on_destroy = true
}

# No secrets, no generated workflow and no PR agent yet. The agent refuses to merge
# without a green check, so it needs a PR_CHECK_WORKFLOW that already lives in the repo;
# wiring one before the repo has CI would install an agent that can never merge anything.
