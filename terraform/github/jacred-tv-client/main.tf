locals {
  repository = "jacred-tv-client"
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

  # Squash-only keeps each merged PR to one commit on main.
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

# No secrets, no variables and no github_repository_file: the repo carries no workflow
# yet. A PR agent needs a PR check to gate on, so it is added once the app has one.
