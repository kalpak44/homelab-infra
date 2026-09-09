# Rules – Comments

How comments are written in this repo, in Terraform, YAML workflows, Justfiles and Dockerfiles alike. Derived from
the review of `terraform/github/kalpak44/workflows/publish.yml`.

## Length comes first

- **One to three lines. Four or more needs a reason.** A comment is read every time the code is; a long one gets
  skipped, which makes it worth less than no comment. Say the one thing that matters and stop.
- **One fact per comment.** If there are two reasons, either pick the load-bearing one or write two comments above
  two different lines.
- **Say what this is and why it is needed. Nothing else.** Not what it scored, not when it was measured, not what
  was tried first. A reader at this line needs the constraint, not the investigation.
- **Never mention another project.** A comment in one repo that explains itself by contrast with `kubectl-awscli`
  or `kalpak44` is unreadable to anyone working only here, and it rots the moment that other repo changes.
- **A generated file names nothing about the repo that generates it, beyond its own banner.** The copies under
  `terraform/github/<repo>/` are read in the target repo, where `gitops/Justfile`, `main.tf` and `.claude/rules/`
  do not exist. State the constraint in terms the target repo can see: "the deploy that looks this up by name",
  not "gitops/Justfile's `apps` list".
- **No inventories of findings, CVE ids, counts, run numbers or PR numbers.** They are true on one day and stale on
  the next, and the code does not behave differently for knowing them. The scan output, the run log and the git
  history already hold them.
- **No narrative, no history lesson.** Git log holds what changed and when. A comment saying what a file used to do,
  over several sentences, is scrollback pretending to be documentation.
- **When the explanation genuinely needs a paragraph, it goes in `.claude/rules/` and the comment points at it.**
  Inline is for the constraint; the rules file is for the argument.

## Substance

- **Say why, never what.** The code states what it does. A comment earns its line by recording the reason, the
  constraint, or the failure it prevents — something a reader cannot recover from the code.
- **Name the failure mode.** Prefer "a zero-byte PDF would be served as a broken download" over "validate the PDF".
  The concrete failure is what stops a later edit from undoing the guard.
- **State the constraint, not the evidence for it.** "an `=` pin breaks when Alpine drops the package" earns its
  line; the scan that proved it does not. Put the evidence in `.claude/rules/` if it is worth keeping.
- **Name coupled files by path.** When editing one file requires editing another, say which, and how many places —
  as a list of paths, not a paragraph explaining each.
- **Explain rejected alternatives where they'll be retried.** "Do not reintroduce X — it was tried and removed
  because Y" prevents the next person repeating the work.
- **No comment that restates the identifier.** `# Set up Java` above `- name: Set up Java` is noise.

## Wording

- **Wrap at 90 columns.** Including the `#` and any leading indentation.
- **Active voice, subject first.** "Actions scopes `type=gha` to this repository", not "`type=gha` is scoped to this
  repository by Actions".
- **Noun form for the noun.** "a cluster deployment", not "a cluster deploy". `deploy` stays the verb — and the job
  name.
- **Closed compounds.** `halfway`, `unbumped`, `rescan` — not `half way`, `un-bumped`.
- **No hyphen after an `-ly` adverb.** "separately attributable", not "separately-attributable".
- **Comma before a conjunction joining two independent clauses.** "…use their own repository path, and none of the
  three need to agree."

## Layout

- **Above the element, never trailing.** A comment sits on its own line(s) directly above what it describes.
- **Single spaces only — never pad to align columns.** Aligned tables inside comments look tidy once and then rot:
  every later edit either re-pads every row or leaves the block ragged, and the diff shows whitespace churn instead
  of the change. Write the list with one space between fields.

  ```yaml
  #   verify-pdf cv-pdf-generator Java 25 / Maven — renders the CV, runs the tests
  #   verify-web web-page-app Node / Vite — formatting, lint, site build
  ```

  not

  ```yaml
  #   verify-pdf   cv-pdf-generator  Java 25 / Maven — renders the CV, runs the tests
  #   verify-web   web-page-app      Node / Vite    — formatting, lint, site build
  ```

- **A generated file opens by saying so.** First two lines name the source of truth and what overwrites the copy:

  ```yaml
  # Managed by homelab-infra — terraform/github/<repo>/workflows/<file>.yml
  # Edits made here in the target repo are overwritten by `just deploy github <repo>`.
  ```

- **Section banners in Terraform** use `# --- Name ---` padded to 88 columns with dashes. This is the one place
  padding is allowed, because the dashes are the rule, not an alignment of fields.

## Accuracy is the point

A block that lists job names, file paths or variables is load-bearing documentation, and a stale name there is worse
than no comment: it reads as authoritative. When renaming anything, grep the comments for the old name.
