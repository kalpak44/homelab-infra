T# Rules – Managed GitHub Repos

`terraform/github/<repo>/` manages a GitHub repository's settings and installs a DeepSeek-backed PR agent into it.
One directory per repo, one R2 state file each — same per-resource model as `cloudflare/` and `proxmox/`.

## Layer layout

```
terraform/github/<repo>/
├── backend.tf              # key = homelab/github/<repo>.tfstate
├── versions.tf             # integrations/github ~> 6.0
├── providers.tf            # provider "github" { owner, token }
├── variables.tf            # github_owner, github_token, deepseek_api_key, deepseek_model, ruleset toggles
├── main.tf                 # import block + repo settings + secrets + workflow file + optional ruleset
├── dependabot.yml          # optional; pushed to .github/dependabot.yml (kalpak44 only)
└── workflows/
    └── ai-pr-agent.yml     # pushed into .github/workflows/ via github_repository_file
```

## What each dir manages

| Resource                       | Purpose                                                              |
|--------------------------------|----------------------------------------------------------------------|
| `github_repository`            | merge settings, `allow_auto_merge`, `delete_branch_on_merge`         |
| `github_actions_secret`        | `DEEPSEEK_APIKEY` for normal workflow runs                           |
| `github_dependabot_secret`     | `DEEPSEEK_APIKEY` for Dependabot-triggered runs (separate store)     |
| `github_actions_variable`      | `DEEPSEEK_MODEL`, `PR_CHECK_WORKFLOW`                                |
| `github_repository_file`       | `.github/workflows/ai-pr-agent.yml` — the agent, and nothing else    |

No `github_repository_ruleset`. One was tried and removed — see the last non-negotiable.

**Every managed repo's entire `.github/` lives here.** Workflows and `dependabot.yml` alike are `github_repository_file`s, so `terraform/github/<repo>/` is the only place any of them is edited and a copy hand-edited in the target repo is overwritten on the next apply. This reverses an earlier rule that CI belonged to the repo: under it, `mite-assistant-mcp`'s publish workflow sat unmanaged and had no deploy job at all, so publishing reached the cluster only through the nightly sweep, and its `ai-pr-agent.yml` merged with `GITHUB_TOKEN` — five dependency PRs merged between 2026-08-20 and 2026-09-03 and none of them ever built. Adopting a workflow means giving it the generated-file banner, wiring a local plus a `github_repository_file`, and bumping its actions by hand from then on.

**One workflow per publishing repo, running on both `pull_request` and `push`.** On a pull request it verifies and stops; on a push to main it verifies, publishes and dispatches `gitops-bump-images` — except in `mite-assistant-mcp`, where the dispatch is batched, see below. `PR_CHECK_WORKFLOW` names that same file, so the agent's merge gate and the thing that ships are never two different pipelines that can drift. `mite-assistant-mcp` had a separate `pr-check.yml` and it was folded in on 2026-09-08. Two details make the shared file safe: the GHCR login is skipped on a pull request, because a Dependabot-triggered run gets a read-only `GITHUB_TOKEN` and would fail on exactly the PRs the check exists for; and `push` and the platform list are both keyed off the event, so an unmerged branch builds one platform and pushes nothing.

**`mite-assistant-mcp` batches the rollout, and that is why its images and its deploys are counted separately.** A morning sweep merges up to ten dependency PRs, so `publish.yml` still builds and pushes an image for every commit on main — `gitops/Justfile`'s `bump-images` reads the tag from the last successful *push* run, and a main commit with no image behind it leaves the Deployment in ImagePullBackOff — but its deploy job holds the rollout when the commit is the squash merge of a bot PR, and `ai-pr-agent.yml` dispatches `PR_CHECK_WORKFLOW` on main once, at the end of its run, to roll out the combined result. Ten merges, ten images, one rollout. The hold is decided from `commits/<sha>/pulls` and `.user.type`, never from the commit author: a squash merge credits the bot as author only while the bot is the sole author, and the agent's own compatibility commits silently make the merger the author. A bot PR merged by hand therefore has no dispatch to follow and degrades to the nightly sweep, which is what the sweep is for.

**Its quality gate is `format:check`, `lint`, `npm test` at 80% coverage and a waited-on SonarCloud gate — all blocking, none of which existed in the repo.** ESLint, Prettier and Jest were added to `mite-assistant-mcp` itself on 2026-09-09 (not Terraform-managed: Terraform owns only `.github/`, and Dependabot has to be able to bump them). The coverage threshold lives in `jest.config.js`, not in a CI step, so `npm test` alone enforces it and a step deleted from the workflow cannot silently disable it; it was verified to fail by raising the threshold. Jest runs native ESM under `--experimental-vm-modules` with `coverageProvider: 'v8'` — the babel provider reports nothing for untransformed ESM, and adding a transform would test transpiled code the container never runs. `SONAR_TOKEN` goes in both secret stores for the usual reason, and the analysis step is guarded on `SONAR_PROJECT_KEY != ''` as well — a missing project key downgrades the gate to nothing while the check still goes green, so verify the step ran, not that the run passed. The SonarCloud project auto-provisioned itself on the first scan; the run that created it still failed, because the scanner reads settings before the project exists.

**An auto-provisioned SonarCloud project needs two fixes before its gate does anything, and both fail in ways that read as authentication errors.** Measured while wiring `mite-assistant-mcp` on 2026-09-09. The project creates itself on the first scan, so nobody has to create it — but it is created with `master` as its main branch, so every analysis of `main` lands on a *short-lived* branch whose gate lookup answers `Not authorized or project not found. Please check the 'SONAR_TOKEN'`. The token is fine; the branch is wrong. Fix it with `project_branches/delete` on the stray `main`, then `project_branches/rename` on `master` — the rename alone fails, because a branch named `main` already exists. Then the gate reports `FAILED` with `status: NONE` and zero conditions, because the project has no new-code definition at all while every "Sonar way" condition is new-code based; the scanner treats not-OK as failure and exits 3. `POST /api/settings/set key=sonar.leak.period value=30` supplies the baseline. Other projects inherit `previous_version` from the instance and never show this, which is why `bunker-party` needed none of it. Note `/api/new_code_periods/*` does not exist on SonarCloud — only `api/settings`.

**Read `alert_status`, not the scanner's exit code, when judging whether the Sonar gate is actually gating.** A gate with no evaluable conditions is not the same as a gate that passed, and both can look green from CI. On a project this new, `new_coverage` and `new_security_rating` stay empty for a while even with `alert_status: OK`, so the new-code conditions are not yet doing work — the overall `coverage` measure is what confirms the lcov upload landed.

**Sonar's taint analysis treats MCP tool arguments as attacker-controlled, and it is right to.** It reported the source as "an attacker can control AI call arguments via prompt injection" flowing 18 steps into the Mite request URL. `miteClient.js` therefore re-validates the time-entry id at its own boundary — a positive safe integer, re-derived through `Number()` so the value reaching the path provably originates there — even though each tool's zod schema already requires one. The schema is one caller away and a second caller would not inherit it. The fix is a guard, never an issue marked won't-fix.

**`publish.yml` is four jobs — verify, image, scan, deploy — and the publish condition is resolved exactly once.** The code gate is split from the image build so it fails in about a minute instead of behind a three-platform build under emulation, and so the run graph names which half broke. `verify` computes `publish` and the seven-character `tag` in its first step and exports them; `image` takes `PUBLISH` from `needs.verify.outputs` rather than recomputing the event/ref test, and re-exports both plus the digest so `scan` and `deploy` need only `needs: image`. Four copies of that condition is the drift this avoids. `image` builds on every trigger and pushes only on main — do not gate the build itself behind the push, or a pull request stops exercising the Dockerfile, which is the check that catches a dependency the image can no longer install.

**The scan paid for itself on its first run, and the fix was the base image.** It reported 10 Critical / 95 High and 293 findings on `node:20-bookworm-slim` — and that Node 20 had been EOL since April 2026 behind an entirely green pipeline. Every candidate was built, scanned against one grype database and smoke-tested before being kept, the same way `release.yml` walks Alpine tags. Measured 2026-09-09 on linux/amd64: bookworm-20 105 C/H, bookworm-22 69, trixie-24 68, alpine-24 18, alpine-24 with `apk upgrade` and npm stripped **0 C/H and 3 findings total**, image 71 MB to 62 MB. The Debian variants bottom out at 7 Criticals whichever release they track, because `perl-base` and glibc carry wont-fix CVEs and sit in the base whether a pure-JavaScript app touches them or not — so no amount of upgrading fixes a Debian base here.

Three findings from that exercise are load-bearing. **`apk upgrade` is not a no-op in this image**, unlike the kubectl-awscli ones measured on 2026-08-24: those install their apk packages unversioned and already resolve current, while this one inherits OpenSSL from a Node base rebuilt on Node's schedule, so `libssl3`/`libcrypto3` lagged one patch and were the entire 18-finding Critical/High surface on their own. **npm is deleted after `npm ci`**, because its vendored tree — tar, pacote, sigstore, minimatch, glob, brace-expansion, cross-spawn — was 19 Critical/High that no change to this project's lockfile could ever reach, and nothing at runtime uses npm. **The image is amd64 only**, which is what made Node 24 reachable at all: Node 24 and 26 publish no `linux/arm/v7`, the old three-platform build cost a QEMU pass each, and the cluster is x86 with no ARM consumer.

**A green pipeline is not evidence the base image is current.** Nothing in verify, Sonar, or the tests could see a four-month-EOL runtime; only an image scan could. That is the argument for keeping the scan even though it never blocks, and the reason `dependabot.yml`'s `node` hold now says to review the pin whenever the scan reports fixable findings against `node` rather than simply holding forever.

**Its `scan` job sits between publish and deploy, and is report-only by design.** syft builds the SBOM and grype scans *that SBOM* rather than the image again, so the packages matched against advisories are exactly the ones reported; two independent catalogings would let the report and the SBOM disagree. It addresses the image by digest, never by tag, because a tag can be overwritten between the push and the scan and the report would then describe an image that is not the one deploying. `--platform linux/amd64` is explicit because the digest is a three-platform manifest list. `deploy` lists it in `needs` for ordering only — `if: always() && needs.build.result == 'success'` is what keeps a scanner outage or a registry timeout from stranding a published image while a failed build still blocks. Do not add `--fail-on`: the blocking security gate here is Sonar, and a Debian base image carries findings Debian has not packaged a fix for, so a threshold would deadlock the rollout. Only Critical and High are tabulated; hundreds of Low/Negligible rows make a summary nobody reads, which is the same as no report.

**Section 7B of its agent prompt puts a gate failure in pre-existing code in scope.** A prettier major that changes a default, an eslint major that adds a recommended rule, or a Sonar rule update raises failures in code the bump never touched, and the default instinct — "unrelated pre-existing failure, leave it open" — blocks that PR and every later one behind the same red gate. The agent must repair it on the PR branch instead, with reformat-only changes in their own commit. Sections 9, 10, 12 and 20 were edited in the same pass because each carried the opposite instruction; a prompt that contradicts itself is worse than either rule alone. The limit is unchanged: fix the code, never the gate — no `eslint-disable`, no widened `.prettierignore`, no lowered coverage threshold, no skipped test, no analysis exclusion. Infrastructure (runner outage, registry timeout, flake) stays out of scope, because that is not code and cannot be fixed on a branch.

**Extracting `requestHandler.js` was a precondition for testing it, not a tidy-up.** `server.js` called `loadConfig()` and `listen()` at module scope, so importing it bound a port and demanded `MITE_BASE_URL` — no test could reach the routing, the bearer check or the session-ownership check, which is where the security-relevant branches are. The handler now takes its collaborators as injectable parameters defaulting to the real ones. `server.js` is a 16-line bootstrap left at 0% coverage on purpose rather than excluded from `collectCoverageFrom`, because an exclusion is the same move as lowering the threshold.

**Dependabot proposes at 05:00 `Europe/Sofia`; the agent sweeps at a fixed 04:00 UTC.** `schedule:` cron has no timezone, and Sofia 05:00 is 02:00 UTC on EEST and 03:00 UTC on EET — a cron set to the summer offset fires *before* the proposals for half the year. 04:00 UTC is one hour late in winter and two in summer. Late is the only direction that cannot fail; early means the sweep finds an empty queue and the PRs wait a day.

**`github-actions` is therefore absent from every `dependabot.yml`.** An action bump merged into a generated workflow is reverted by the next apply and re-opened by Dependabot the next morning, for ever. Dependabot cannot watch the copies here either — it only scans `.github/workflows/`, and here they are ordinary files under `terraform/`. This has a real cost in `plugin-noco-tools`, whose `publish.yml` pins four actions to commit SHAs against a retagged release (CWE-829): that entry existed to keep the pins from rotting, and those SHAs now move by hand.

**Dependabot runs daily at 05:00 UTC in every repo that has an agent**, an hour before the agent's `0 6 * * *` sweep, so a proposal never waits more than an hour. `mite-assistant-mcp` is the one exception — 05:00 `Europe/Sofia` against a 04:00 UTC sweep, see above. `kubectl-awscli` and `postgres-awscli` get no `dependabot.yml`: their `release.yml` agent resolves and writes the Dockerfile pins itself, so a second updater would fight it.

**Exception — `kalpak44` centralizes all of `.github/`.** Its `publish.yml`, `ai-pr-agent.yml` and `dependabot.yml` are
all `github_repository_file`s, so `terraform/github/kalpak44/` is the only place any of them is edited. The reason is
`publish.yml`'s last job: it dispatches `gitops-bump-images` with `app=personal-web-page`, a name that must match
`gitops/Justfile`'s `apps` list, and keeping the workflow and that list in one repo means a rename cannot break the
deploy silently. Renaming the file is therefore a four-place change — `workflows/publish.yml`, its own `paths:` filter,
`PR_CHECK_WORKFLOW`, and the `apps` list.

**A centralized workflow must not also be Dependabot's target.** `kalpak44`'s `dependabot.yml` deliberately omits the
`github-actions` ecosystem: an action bump merged into a generated workflow is reverted by the next
`just deploy github kalpak44` and then reopened on Dependabot's next run. Action versions in generated workflows are
bumped here instead, and Dependabot cannot watch them here either — it only scans `.github/workflows/`, and in this
repo they are ordinary files under `terraform/`. The mirror layout is deliberate: `<repo>/workflows/` maps to
`.github/workflows/`, `<repo>/dependabot.yml` to `.github/dependabot.yml`.

**Exception — `bunker-party` centralizes all of `.github/` too, and uses Dependabot because Renovate cost a
credential.** Its `ai-pr-agent.yml`, `publish.yml` and `dependabot.yml` are all `github_repository_file`s. `publish.yml`
is one job that formats, builds, tests and runs SonarCloud with `-Dsonar.qualitygate.wait=true`, publishes
`ghcr.io/kalpak44/bunker-party` only when the ref is main, and then dispatches `gitops-bump-images` for
**`bunker-game-app`** — a gitops dir name that is not the repo name, which is why the workflow and `gitops/Justfile`'s
`apps` list belong in one repo. The deploy job keys off the build job's `tag` output rather than repeating the
event/ref test, so the publish and deploy conditions cannot drift apart. Self-hosted Renovate was removed rather than
repaired: its `RENOVATE_TOKEN` had expired, and every nightly run extracted ten pending updates and then 403'd pushing
each branch while still reporting success — no PR since February. Dependabot needs no token, so the fix removed a
credential instead of adding one.

**`proklinator-app` centralizes all of `.github/` as well, and it has exactly three workflows.** `publish.yml`,
`ai-pr-agent.yml` and `ai-issue-resolver-agent.yml` are all `github_repository_file`s, as is `dependabot.yml`.
`publish.yml` is its CI, its `PR_CHECK_WORKFLOW` and its deploy trigger in one: verify → image → scan → deploy, building
**two** images from the same commit (`proklinator-app` and `proklinator-api`, same short-SHA tag) and dispatching
`gitops-bump-images` for `proklinator`. Adding a third image means adding it to `gitops/Justfile`'s `apps` list too, or
its Deployment sits on an older tag. Its `dependabot.yml` keeps the site and the API in separate npm entries with
separate groups on purpose — one lockfile each, one image each, so a failure is attributable. Dependabot proposes at
05:00 `Europe/Sofia` against the sweep's fixed 04:00 UTC, for the reason given above. `node` is held in the docker entry
because Node 24 is pinned in five places at once: both Dockerfiles, `publish.yml`'s verify job and both agents.

**Its gate is `format:check`, `lint`, two vitest suites and two waited-on SonarCloud gates — all blocking, and formatting
and lint used to be `continue-on-error`.** Vitest, jsdom, Testing Library and supertest were added to the repo itself
(not Terraform-managed: Terraform owns only `.github/`, and Dependabot has to be able to bump them). Two suites and two
Sonar projects rather than one of each, because the site and the API are separate lockfiles and separate images:
`proklinator-app` analyses `src/` against `coverage/site/lcov.info`, `proklinator-app-api` analyses `backend/src/`
against `coverage/api/lcov.info`, and a failure names which half broke. Both scanners run in the same workspace, so each
needs its own `sonar.working.directory`. Thresholds live in `vitest.site.config.js` and `vitest.api.config.js`, never in
a CI step, so a step deleted from the workflow cannot silently disable them. `backend/src/app.js` is held at 100% by a
per-file threshold — verified to fail by raising one — while `server.js` sits at 0: it binds a port at module scope, so
v8 cannot see it and `test/api/server.test.js` spawns it as a real process instead. Leaving it in the report at 0 rather
than excluding it is deliberate; an exclusion is the same move as lowering a threshold.

**Extracting `backend/src/app.js` was a precondition for testing the API, not a tidy-up.** `server.js` called `listen()`
at module scope, so importing it bound a port and read the environment — no test could reach the catalog validation or
the checkout session builder, which is where every price the buyer is charged is resolved. The app now takes its Stripe
client and catalog as injectable parameters defaulting to the real ones.

**Exception — `proklinator-app` resolves issues end to end in one workflow.** `ai-issue-resolver-agent.yml` implements
an issue labelled `ai:ready`, drives the built app in a browser, opens a pull request, waits for `publish.yml` and
merges it. **The issue is the state machine** (`ai:*` labels), the pull request is scratch space, and the fix-round
number is *derived* by counting the branch's failed check runs — never stored, so it cannot drift. A separate
`ai-pr-review.yml` used to do the merging half; folding it in removed a second `pull_request_target` workflow and the
review ping-pong between them. Five constraints hold the design together and must not be relaxed:

- **The merge is computed in bash, in the `land` job, and no model runs there.** Browser QA in `work` and the check
  conclusions in `land` are both evaluated before anything merges. The model implements and repairs; it has no path to
  a merge those did not allow.
- **`land` re-reads the head SHA and refuses if it moved during the wait.** Otherwise a push landing mid-wait merges on
  a green that belongs to an older commit.
- **The resolver pushes, opens and merges with `GH_ADMIN_TOKEN`.** A pull request opened with `GITHUB_TOKEN` triggers no
  workflow runs at all, so it would never get the check it is waiting for, and a merge made with it starts nothing on
  main — the images would never publish. It also makes the author a human account, which is why `ai-pr-agent.yml`'s bot
  sweep leaves these pull requests alone with no change to that file. Issue labels and comments still go through
  `GITHUB_TOKEN`; the PAT is read-only on issues.
- **Browser QA blocks in `work`, before `land` is reached.** CI does not run a browser, so a change that builds and is
  broken on screen would otherwise merge green. A blocking verdict fails the job, which skips `land` outright.
- **`AI_MAX_FIX_ROUNDS` is enforced in both jobs.** `plan` refuses on the way in and `land` refuses to dispatch past it,
  so neither half can run away alone. Each round is a model run plus a browser QA pass.

**Exception — the container-image repos.** `kubectl-awscli` and `postgres-awscli` get `workflows/release.yml` instead
of `ai-pr-agent.yml`, and that file *is* their CI. It is one workflow, and now one **job**, because every step needs
the working tree the step before it produced and because nothing may reach the registry until the whole chain has
passed: resolve upstream (AI) → build → smoke → scan → remediate → rescan → version → commit → publish. It also has to
be one run because a push made with `GITHUB_TOKEN` does not trigger another workflow run, so the agent's commit would
never fire a push-triggered build. It runs weekly (Mondays 05:00 UTC), on dispatch, and on push. These repos have no
`PR_CHECK_WORKFLOW` and no PR agent.

**The build and the scan run on every trigger, including quiet weeks.** A week where no version moved still rebuilds,
rescans, and refreshes the SARIF; it just does not publish. Do not add an early exit that skips the scan when the agent
found nothing — the vulnerability picture changes without the pins changing, and that is the whole point of a weekly
run.

**No versions file.** The Dockerfile holds the pins; the newest `## vX.Y.Z` heading in `CHANGELOG.md` is the published
version. Do not reintroduce a `versions.env` — it was tried and removed. It only duplicated what the Dockerfile already
states, and gave the agent a second place to write a number that the build would then not actually use.

**The agent does not choose the version number.** It writes the literal `## vNEXT`; the workflow computes the real
number from measured facts (see below) and substitutes it. Do not hand that decision back to the prompt — it was the
one number the agent had no way to verify against anything.

**Versioning is SemVer, computed in bash.** A shipped tool's *major* moving, an apk package being dropped, or an
entrypoint/command/user/workdir change is breaking; the Alpine minor or a tool *minor* moving is a feature; everything
else that changes the image is a fix. Mapped through SemVer's pre-1.0 clause (§4), so at `0.y.z` breaking and feature
both bump the minor, and only past 1.0.0 does breaking bump the major. Previous tool versions come from the
`io.homelab.tools.*` labels on `:latest`, which is why those labels must keep being written.

**Never pin an apk package to an exact version.** `postgresql-client` and `aws-cli` are installed unversioned on
purpose: an `=version` pin breaks the moment Alpine drops that package from its repo, and `postgresql-client` without a
number already resolves to whichever major the release ships (18 on Alpine 3.23 and 3.24). The provenance gate rejects
an `=` in the package list for exactly this reason. Bumping the Alpine tag is what moves these tools.

**`apk upgrade` is a no-op here — do not re-add it.** Measured on both images on 2026-08-24: identical Critical/High
counts with and without it. The official `alpine:X.Y` tag is rebuilt at the newest patch level and `apk add --no-cache`
already fetches current packages. It buys a layer and the appearance of hardening.

**Security remediation may jump more than one Alpine minor; the version agent may not.** Measured on `kubectl-awscli`:
3.22 → 3.23 *raised* Criticals from 8 to 10, while 3.22 → 3.24 cut them to 2. A remediation loop capped at one step
would propose the regression, measure it, revert, and repeat every week for ever. The search therefore walks candidate
tags newest-first, which is safe because every candidate is built, smoke-tested and rescanned before it is kept — the
evidence the one-step rule approximates is produced directly. The version agent keeps its one-step climb; that is about
deliberate, attributable tooling movement, which is a different question.

**The smoke suite is the compatibility contract, and it must have teeth.** It checks every binary the image promises,
the real entrypoint, the uid, the TLS trust store, and for `postgres-awscli` the MODE dispatch plus both scripts'
refusal to run without their variables. It also imports `awscli`, `awscli.botocore`, `jmespath`, `urllib3` and
`cryptography` and compiles the exact JMESPath expression `backup.sh` hands to `aws s3api --query` — that last one is
what stops a remediation from "fixing" the two `py3-jmespath` Criticals by removing the package the retention policy
depends on. Verified to fail on a deliberately broken image; a gate that cannot fail is not a gate.

**The publish policy is explicit and must stay non-deadlocking.** Blocking on every Critical/High would freeze both
images for ever: on the newest Alpine, all the residual findings are either unfixed upstream or fixed upstream but not
packaged by Alpine. So `enforce` blocks only a measured regression against `:latest` — rescanned in the same run with
the same grype database, so database growth is never mistaken for a regression. `strict` and `report-only` exist as
dispatch inputs. Refusing to publish an image whose remaining CVEs cannot be reached would pin consumers to an older
image carrying the same CVEs *plus* the ones already fixed.

**The prompt says "never guess"; the bash gates are what make it true.** Between the agents and the commit: scope (only
`Dockerfile` and `CHANGELOG.md` may change, and a Dockerfile change needs a `## vNEXT`), provenance (every pin
re-resolved against the registry and upstream, no backwards moves, no exact apk pins), smoke (the contract above),
accept-or-revert on every remediation (Criticals must not rise, Critical+High must strictly fall, no tool major may
move), and the publish policy. Everything reaches `main` with no human review, so these must stay in bash — never relax
one into a prompt instruction. Terraform owns the workflow only; it never manages `Dockerfile` or `CHANGELOG.md`, so a
bump never fights it.

**A push only cuts a release when it changed something that ends up in the image.**
Terraform re-syncs `release.yml` into the repo on every `just deploy github <repo>`, and that push runs the workflow. A
push touching only `CHANGELOG.md`, `README.md`, `LICENSE`, `SECURITY.md`, `.gitignore` or `.github/` rebuilds and
rescans but does not publish. Without this, every `terraform apply` minted a version for an image nobody changed — it
did, twice, before the rule existed. A remediation still publishes on such a push, because that genuinely changes the
image.

**Every release reports what it fixed and what it ships.** `resolved()` diffs the published image's scan against the
candidate's to list the Critical/High findings this release actually removed, grouped by package with their ids;
`inventory()` probes the built image for every tool and its version. Both go into the CHANGELOG entry, the release
notes and the run summary. The inventory is probed from the image about to ship — never restated from the pins, which
is the whole point: `aws-cli` and the PostgreSQL client have no pin to restate. Read package versions with
`apk list -I <pkg>`, not `apk info -v <pkg>` — the latter prints the description, not the version.

**Roll a rejected attempt back with a saved copy, not `git checkout -- Dockerfile`.** The version agent's edits are
uncommitted working-tree changes, so checking out from `HEAD` silently discards the base bump the run just made and
validated. The remediation steps snapshot the Dockerfile to `/tmp/sec/Dockerfile.incumbent` and restore from that.

## Non-negotiables

- **Adopt, never create.** Existing repos come in via an `import` block, not a fresh `github_repository`. The import
  block is a no-op once the resource is in state, so `apply` stays idempotent from a cold start.
- **`archive_on_destroy = true`** on every `github_repository`. `just destroy github <repo>` must never delete a repo.
- **The key goes in both secret stores.** Dependabot-triggered runs read from the Dependabot store, not the Actions
  store. A key in only one of them is empty on exactly the PRs the agent is meant to handle.
- **The agent workflow is generated, not hand-edited.** It lives in `workflows/` here and is overwritten in the target
  repo on every apply. Edits made in the target repo are lost.
- **Bot PRs only.** The agent is instructed to match on `is_bot`, not on the login — `gh pr list` reports Dependabot as
  `app/dependabot`, not `dependabot[bot]`. Human PRs are never merged.
- **The agent is the merge gate, and it merges sequentially.** No `gh pr merge --auto`: auto-merge is asynchronous, so
  arming several dependency PRs at once makes them all fire together and collide on the same lockfile. The agent waits
  for checks, merges one PR, confirms it landed, then starts the next.
- **`PR_CHECK_WORKFLOW` must name a workflow that lives in the target repo and runs on `pull_request`.** The agent
  refuses to merge without a green check, so a repo with no PR CI will simply never merge anything. That workflow also
  needs a `workflow_dispatch` trigger, because the agent starts it for PRs whose head commit has no checks — a PR
  opened before the check existed gets none retroactively.
- **No branch ruleset.** A ruleset's `pull_request` rule also rejects Terraform's own commits to the workflow files it
  manages (`409 Changes must be made through a pull request`), which then needs a `bypass_actors` entry for the admin
  role plus `depends_on` ordering. Not worth it when the agent already gates on CI.
- **Codex talks to DeepSeek directly.** DeepSeek serves the OpenAI Responses API at `/v1/responses`, the only wire
  protocol Codex still supports (`wire_api = "chat"` was removed upstream). Do not reintroduce a translating proxy:
  LiteLLM's Responses→chat bridge drops tool-result messages and DeepSeek rejects the resulting message sequence.

## Env vars

| TF var                    | Env var           | Notes                                                          |
|---------------------------|-------------------|----------------------------------------------------------------|
| `TF_VAR_github_token`     | `GH_ADMIN_TOKEN`  | classic `repo` + `workflow`, or fine-grained with write on Administration / Contents / Secrets / Dependabot secrets / Variables / Workflows |
| `TF_VAR_github_owner`     | `GH_OWNER`        | defaults to `kalpak44`                                         |
| `TF_VAR_deepseek_api_key` | `DEEPSEEK_APIKEY` | already present in the shell locally and as a repo secret in CI |
| `TF_VAR_sonar_token`      | `SONAR_TOKEN`     | `bunker-party` only, and optional: mirrors the key into the Dependabot store so publish.yml's quality gate runs on Dependabot PRs. Unset leaves the stored secret untouched |

Secret names cannot start with `GITHUB_` (reserved by GitHub) — hence `GH_ADMIN_TOKEN` / `GH_OWNER`.

## Checklist – managing a new repo

1. `cp -r terraform/github/kalpak44 terraform/github/<repo>`.
2. Edit `backend.tf` (state key `homelab/github/<repo>.tfstate`), and in `main.tf` the `repository` /
   `default_branch` locals and the repo settings so the first plan is a no-op on anything you don't intend to change.
   Check the live settings first: `gh api repos/<owner>/<repo>`.
3. Add `<repo>` to the `options:` list in `.github/workflows/github-{deploy,destroy}.yml`.
4. Add a description line to `terraform/Justfile`'s `list` recipe under the GitHub section.
5. Add a row to the **Managed GitHub repos** table in `README.md`.
6. Apply: `just deploy github <repo>`.