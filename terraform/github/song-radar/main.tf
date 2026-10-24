locals {
  repository = "song-radar"
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

  # Squash-only keeps each merged PR to one commit on main.
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

# No secrets, no generated workflows and no maintenance agent yet: the repo holds no app.
# The agent refuses to merge without a green PR check, so wiring it before there is a
# pipeline to be green installs something that can only sit idle.
