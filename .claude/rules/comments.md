# Rules – Comments

How comments are written in this repo, in Terraform, YAML workflows, Justfiles and Dockerfiles alike. Derived from
the review of `terraform/github/kalpak44/workflows/publish.yml`.

## Substance

- **Say why, never what.** The code states what it does. A comment earns its line by recording the reason, the
  constraint, or the failure it prevents — something a reader cannot recover from the code.
- **Name the failure mode.** Prefer "a zero-byte PDF would be served as a broken download" over "validate the PDF".
  The concrete failure is what stops a later edit from undoing the guard.
- **Record the measurement, not the impression.** If a decision came from an observation, state it: dates, counts,
  versions ("measured on both images on 2026-08-24: identical Critical/High counts").
- **Name coupled files by path.** When editing one file requires editing another, say which, and how many places.
  A rename that must happen in four places should say "four places" and list them.
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
