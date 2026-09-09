# Rules - Git

- Commit messages must be a single short imperative line - no body, no trailers, no `Co-Authored-By`.

- **"use `git-kalpak44`" means run that function in the repo being committed to, before the
  first commit.** It is a zsh function in `~/.zshrc` — reachable from the tool shell, not a
  binary on `PATH` — and it sets `user.name` / `user.email` **locally** in the current repo to
  `Pavel Usanli <pavel.usanli@gmail.com>`, refusing to run outside a work tree. It is the
  identity for the `kalpak44` repos; this machine's global identity is the work one
  (`pau@foryouandyourcustomers.com`), so a clone of a `terraform/github/<repo>` target picks up
  the wrong author unless the function is run first. Correcting it after a push means rewriting
  the author and force-pushing a branch that CI has already built.
