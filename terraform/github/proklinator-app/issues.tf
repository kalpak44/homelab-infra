# Issue structure — labels only, deliberately.
#
# Terraform owns the *shape* of the issue tracker, not its contents. Labels and the
# has_issues flag are stable and declarative, so they belong here. Individual tickets do
# not: an issue is closed, reopened, retitled and commented on constantly, and a resource
# that wants to own that state fights every one of those edits. `github_issue` exists in
# the provider, but pointing it at a live backlog means Terraform reverting a title
# someone fixed by hand, and REST cannot delete an issue anyway — removing one from the
# config cannot do what the config implies. Tickets get created by people and by the
# triage agent; only their vocabulary is managed here.
#
# The `ai:*` labels are the loop's control plane. They are how a human says "this one is
# actually actionable", how the implementer claims work so two runs cannot pick the same
# issue, and how it hands something back when it needs a decision it is not allowed to
# make. They are not decoration — the workflows key off them.

locals {
  # Colour convention: red = blocked/urgent, purple = agent lifecycle, blue = type,
  # grey = area. GitHub wants the hex without the leading '#'.
  issue_labels = {
    # --- agent lifecycle ---------------------------------------------------------
    "ai:ready" = {
      color       = "5319e7"
      description = "Triaged and actionable — the implementer agent may pick this up"
    }
    "ai:in-progress" = {
      color       = "8a63d2"
      description = "Claimed by the implementer agent; a branch exists"
    }
    "ai:blocked" = {
      color       = "b60205"
      description = "Needs a human decision the agent is not allowed to make"
    }
    "ai:review" = {
      color       = "c5a3ff"
      description = "Implemented — a pull request is open and under review"
    }

    # --- type --------------------------------------------------------------------
    "type:bug" = {
      color       = "d73a4a"
      description = "Something is broken"
    }
    "type:feature" = {
      color       = "0e8a16"
      description = "New behaviour"
    }
    "type:chore" = {
      color       = "fbca04"
      description = "Maintenance, tooling, dependencies"
    }
    "type:docs" = {
      color       = "0075ca"
      description = "Documentation only"
    }

    # --- priority ----------------------------------------------------------------
    "p0" = {
      color       = "b60205"
      description = "Drop everything"
    }
    "p1" = {
      color       = "d93f0b"
      description = "Next"
    }
    "p2" = {
      color       = "fef2c0"
      description = "Whenever"
    }

    # --- area — mirrors the app's own structure ----------------------------------
    "area:book" = {
      color       = "bfd4f2"
      description = "Pagination, spreads, page turning, geometry"
    }
    "area:order" = {
      color       = "bfd4f2"
      description = "Order flow, pricing, checkout"
    }
    "area:ui" = {
      color       = "bfd4f2"
      description = "Layout, styling, responsive behaviour"
    }
    "area:build" = {
      color       = "bfd4f2"
      description = "Vite, Docker, CI, deployment"
    }
  }
}

resource "github_issue_label" "this" {
  for_each = local.issue_labels

  repository  = github_repository.this.name
  name        = each.key
  color       = each.value.color
  description = each.value.description
}