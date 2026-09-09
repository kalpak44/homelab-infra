# Rules - Git

- Commit messages must be a single short imperative line - no body, no trailers, no `Co-Authored-By`.

- **Every commit we make is authored `Pavel Usanli <pavel.usanli@gmail.com>`, configured per
  repo.** Before the first commit in any working tree — this repo included, and every
  `terraform/github/<repo>` target we clone — read `git config --local user.name` and
  `user.email`, then set them with `git config user.name` / `user.email` if they differ. It is a
  check made every time, not a one-off: a clone carries no local identity of its own, so there
  is nothing to inherit but the wrong one.

- **Never `git config --global`.** The machine's global identity belongs to unrelated work and
  is correct there, so a global override would silently retag those repositories too. A fresh
  clone inherits it, which is how `3a02211` in `mite-assistant-mcp` was pushed on 2026-09-09
  under the wrong address, unlinked from the `kalpak44` account. Correcting an author already
  pushed means amending and force-pushing: that orphans the CI run the old commit produced and
  leaves every open PR branch diverged from the base, which then has to be rebased.

- **`homelab-infra <homelab-infra@users.noreply.github.com>` is a bot identity, not ours.** It
  belongs to automation: the `commit_author` / `commit_email` on every `github_repository_file`
  in `terraform/github/`, and this repo's history up to `598f944`. Leave those alone — nothing
  was rewritten, so the log carries both identities by design. Do not use it for a commit we
  make, and do not change automation to use ours.
