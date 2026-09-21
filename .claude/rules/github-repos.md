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
├── agent-prompts/
│   └── ai-maintenance-agent.md   # pushed into .github/agent-prompts/
└── workflows/
    └── ai-maintenance-agent.yml  # pushed into .github/workflows/
```

## What each dir manages

| Resource                       | Purpose                                                              |
|--------------------------------|----------------------------------------------------------------------|
| `github_repository`            | merge settings, `allow_auto_merge`, `delete_branch_on_merge`         |
| `github_actions_secret`        | `DEEPSEEK_APIKEY` for normal workflow runs                           |
| `github_dependabot_secret`     | `DEEPSEEK_APIKEY` for Dependabot-triggered runs (separate store)     |
| `github_actions_variable`      | `DEEPSEEK_MODEL`, `PR_CHECK_WORKFLOW`                                |
| `github_repository_file`       | `.github/workflows/ai-maintenance-agent.yml` and the prompt it runs           |

No `github_repository_ruleset`. One was tried and removed — see the last non-negotiable.

**Every managed repo's entire `.github/` lives here.** Workflows and `dependabot.yml` alike are `github_repository_file`s, so `terraform/github/<repo>/` is the only place any of them is edited and a copy hand-edited in the target repo is overwritten on the next apply. This reverses an earlier rule that CI belonged to the repo: under it, `mite-assistant-mcp`'s publish workflow sat unmanaged and had no deploy job at all, so publishing reached the cluster only through the nightly sweep, and its `ai-maintenance-agent.yml` merged with `GITHUB_TOKEN` — five dependency PRs merged between 2026-08-20 and 2026-09-03 and none of them ever built. Adopting a workflow means giving it the generated-file banner, wiring a local plus a `github_repository_file`, and bumping its actions by hand from then on.

**One workflow per publishing repo, running on both `pull_request` and `push`.** On a pull request it verifies and stops; on a push to main it verifies, publishes and dispatches `gitops-bump-images` — except in `mite-assistant-mcp`, where the dispatch is batched, see below. `PR_CHECK_WORKFLOW` names that same file, so the agent's merge gate and the thing that ships are never two different pipelines that can drift. `mite-assistant-mcp` had a separate `pr-check.yml` and it was folded in on 2026-09-08. Two details make the shared file safe: the GHCR login is skipped on a pull request, because a Dependabot-triggered run gets a read-only `GITHUB_TOKEN` and would fail on exactly the PRs the check exists for; and `push` and the platform list are both keyed off the event, so an unmerged branch builds one platform and pushes nothing.

**`mite-assistant-mcp` batches the rollout, and that is why its images and its deploys are counted separately.** A morning sweep merges up to ten dependency PRs, so `publish.yml` still builds and pushes an image for every commit on main — `gitops/Justfile`'s `bump-images` reads the tag from the last successful *push* run, and a main commit with no image behind it leaves the Deployment in ImagePullBackOff — but its deploy job holds the rollout when the commit is the squash merge of a bot PR, and `ai-maintenance-agent.yml` dispatches `PR_CHECK_WORKFLOW` on main once, at the end of its run, to roll out the combined result. Ten merges, ten images, one rollout. The hold is decided from `commits/<sha>/pulls` and `.user.type`, never from the commit author: a squash merge credits the bot as author only while the bot is the sole author, and the agent's own compatibility commits silently make the merger the author. A bot PR merged by hand therefore has no dispatch to follow and degrades to the nightly sweep, which is what the sweep is for.

**Its quality gate is `format:check`, `lint`, `npm test` at 80% coverage and a waited-on SonarCloud gate — all blocking, none of which existed in the repo.** ESLint, Prettier and Jest were added to `mite-assistant-mcp` itself on 2026-09-09 (not Terraform-managed: Terraform owns only `.github/`, and Dependabot has to be able to bump them). The coverage threshold lives in `jest.config.js`, not in a CI step, so `npm test` alone enforces it and a step deleted from the workflow cannot silently disable it; it was verified to fail by raising the threshold. Jest runs native ESM under `--experimental-vm-modules` with `coverageProvider: 'v8'` — the babel provider reports nothing for untransformed ESM, and adding a transform would test transpiled code the container never runs. `SONAR_TOKEN` goes in both secret stores for the usual reason, and the analysis step is guarded on `SONAR_PROJECT_KEY != ''` as well — a missing project key downgrades the gate to nothing while the check still goes green, so verify the step ran, not that the run passed. The SonarCloud project auto-provisioned itself on the first scan; the run that created it still failed, because the scanner reads settings before the project exists.

**An auto-provisioned SonarCloud project needs two fixes before its gate does anything, and both fail in ways that read as authentication errors.** Measured while wiring `mite-assistant-mcp` on 2026-09-09. The project creates itself on the first scan, so nobody has to create it — but it is created with `master` as its main branch, so every analysis of `main` lands on a *short-lived* branch whose gate lookup answers `Not authorized or project not found. Please check the 'SONAR_TOKEN'`. The token is fine; the branch is wrong. Fix it with `project_branches/delete` on the stray `main`, then `project_branches/rename` on `master`. Delete first only when that stray branch exists: a scan that never reached the gate leaves the project with `master` alone, and there the rename is the whole fix — measured across `proklinator-app`, which had both, and `proklinator-app-api`, which had only `master`. Every project needs this separately, so a repo analysing two of them needs it twice. Then the gate reports `FAILED` with `status: NONE` and zero conditions, because the project has no new-code definition at all while every "Sonar way" condition is new-code based; the scanner treats not-OK as failure and exits 3. Fix that with `POST /api/project_analyses/set_baseline` naming the latest analysis on `main` — from `project_analyses/search?project=X&branch=main`. Other projects inherit `previous_version` from the instance and never show this, which is why `bunker-party` needed none of it.

**Do not reach for `sonar.leak.period` — it is gone, and `settings/set` will not tell you.** It was tried on both `proklinator-app` projects: `POST /api/settings/set key=sonar.leak.period value=30` answered `204`, and reading that one key back answered `30`, so it looked applied. It was not. The key is absent from `settings/list_definitions`, absent from an unfiltered `settings/values`, and the next analysis still produced zero conditions — `settings/set` stores an unrecognised key without complaint and the single-key read hands it back. Only `set_baseline` moves the gate. `/api/new_code_periods/*` does not exist on SonarCloud either; `api/webservices/list` is what settles which endpoints do.

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

**`github-actions` is therefore absent from every `dependabot.yml`.** An action bump merged into a generated workflow is reverted by the next apply and re-opened by Dependabot the next morning, for ever. Dependabot cannot watch the copies here either — it only scans `.github/workflows/`, and here they are ordinary files under `terraform/`. This has a real cost in `noco-google-connector-web-page`, whose `publish.yml` pins four actions to commit SHAs against a retagged release (CWE-829): that entry existed to keep the pins from rotting, and those SHAs now move by hand.

**Dependabot runs daily at 05:00 UTC in every repo that has an agent**, an hour before the agent's `0 6 * * *` sweep, so a proposal never waits more than an hour. `mite-assistant-mcp` is the one exception — 05:00 `Europe/Sofia` against a 04:00 UTC sweep, see above. `kubectl-awscli` and `postgres-awscli` get no `dependabot.yml`: their `release.yml` agent resolves and writes the Dockerfile pins itself, so a second updater would fight it.

**Exception — `kalpak44` centralizes all of `.github/`.** Its `publish.yml`, `ai-maintenance-agent.yml` and `dependabot.yml` are
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
credential.** Its `ai-maintenance-agent.yml`, `publish.yml` and `dependabot.yml` are all `github_repository_file`s. `publish.yml`
is one job that formats, builds, tests and runs SonarCloud with `-Dsonar.qualitygate.wait=true`, publishes
`ghcr.io/kalpak44/bunker-party` only when the ref is main, and then dispatches `gitops-bump-images` for
**`bunker-game-app`** — a gitops dir name that is not the repo name, which is why the workflow and `gitops/Justfile`'s
`apps` list belong in one repo. The deploy job keys off the build job's `tag` output rather than repeating the
event/ref test, so the publish and deploy conditions cannot drift apart. Self-hosted Renovate was removed rather than
repaired: its `RENOVATE_TOKEN` had expired, and every nightly run extracted ten pending updates and then 403'd pushing
each branch while still reporting success — no PR since February. Dependabot needs no token, so the fix removed a
credential instead of adding one.

**`proklinator-app` centralizes all of `.github/` as well, and it has exactly three workflows.** `publish.yml`,
`ai-maintenance-agent.yml` and `ai-issue-resolver-agent.yml` are all `github_repository_file`s, as is `dependabot.yml`.
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
  main — the images would never publish. It also makes the author a human account, which is why `ai-maintenance-agent.yml`'s bot
  sweep leaves these pull requests alone with no change to that file. Issue labels and comments still go through
  `GITHUB_TOKEN`; the PAT is read-only on issues.
- **Browser QA blocks in `work`, before `land` is reached.** CI does not run a browser, so a change that builds and is
  broken on screen would otherwise merge green. A blocking verdict fails the job, which skips `land` outright.
- **`AI_MAX_FIX_ROUNDS` is enforced in both jobs.** `plan` refuses on the way in and `land` refuses to dispatch past it,
  so neither half can run away alone. Each round is a model run plus a browser QA pass.

**Feedback re-enters through the same label, and a revision never opens a second pull request.** `ai:ready` on an issue
that already has an open pull request means *revise*: `plan` switches mode instead of skipping, `work` keeps the branch,
and the agent is given only the comments left on either thread since the branch head — handed the original description
it rebuilds what is already there. What the round pushed is reported on both threads in bash, never by the prompt, and a
round that pushes nothing marks the issue `ai:blocked` and fails the job: the commits already on the branch are green, so
`land` would otherwise merge exactly the work the comment asked to change. The fix-round count is still derived from the
branch's failed check runs, which means a revision cannot reset it — `plan` says so in its summary when they are already
spent.

**The resolver reads the Sonar gate instead of guessing at it.** `sonar-scanner` exits 3 for any gate that is not OK, so
the CI log names no rule at all. `work` fetches the gate status, every failing condition with its threshold and every
unresolved issue — with the source-to-sink flow for a taint finding — from SonarCloud's API into the prompt, using the
`SONAR_TOKEN` and project-key variables the repo already carries, so this costs no new credential. It reads
`pullRequest=<n>` when there is one and `branch=main` otherwise, and it runs in every mode: a BLOCKER left on main is
inherited by every branch cut from it and fails their gates too, which is what makes one unfixed finding look like an
intermittent CI failure.

**An accidental close is recovered; a merge is not.** `ai:ready` on an issue whose pull request was closed unmerged opens
a new one from the branch, which is still there, and on a closed issue it reopens the issue first. A merged pull request
from that branch is the one closure that was not an accident, so the run stops and asks for a new issue rather than
rebuilding shipped work.

**`mac-calendar-mcp` and `code-viewer-bot` share one shape: two workflows, and the release is keyed on a tag.** `release.yml` is the PR check *and* the publisher — `format:check`, `lint`, jest against a coverage floor in `jest.config.js`, and a waited-on SonarCloud gate on every pull request and every push to main; the build, release and (for `code-viewer-bot`) the Marketplace publish run only for a `v*` tag. `ai-maintenance-agent.yml` sweeps the bot PRs and, once at the end, cuts that tag — and cuts one to complete a release whose own run failed, since the tag it broke on cannot be moved. That second case is gated on the failed run having been a *tag* run: the same workflow verifies pull requests and main, and a verify failure that mints a version is a number naming no release. `FAILED_RUN_BRANCH` holds the tag on a tag run, which is what tells them apart. Both files are byte-identical between the repos apart from the banner, so a fix to one is a copy to the other.

**The agent picks the bump word; bash picks the number.** The agent writes `{"bump":"patch|minor|major"}` to `BUMP_FILE` and nothing else — it may not edit `package.json` or create a tag. The step after it computes the version through SemVer §4 (so `major` lands on the minor below 1.0.0), commits, tags annotated and pushes. This keeps the existing rule intact: the number is the one value a model cannot verify, so it is not the model's to write. An unrecognised word is treated as `patch` and logged as a warning rather than failing the sweep.

Four things about this pair are load-bearing. **One sweep cuts one release**, because the tag is cut after the last PR, not per merge — a ten-PR morning produces one version. **Keying the release on the tag is what stops the bump loop**: the version commit lands on main, and main only verifies. **The agent's `actions/checkout` must pass `token: GH_ADMIN_TOKEN`** — `persist-credentials` otherwise stores `GITHUB_TOKEN`, and GitHub starts no workflow run for a push made with it, so the tag would land and nothing would build it. And **`runner.temp` cannot appear in a job-level `env:` block**; it makes the whole workflow unparseable, which surfaces as a run named after the file path instead of the workflow.

**The prompt is a file, not a heredoc, and it is pushed into the target repo.** `agent-prompts/ai-maintenance-agent.md` maps to `.github/agent-prompts/ai-maintenance-agent.md` the same way `workflows/` maps to `.github/workflows/`, and the workflow reads it from its own checkout. A thousand lines of prompt inside YAML was neither readable nor reviewable; splitting them leaves the workflow at about 300 lines that only decide *whether* there is work. The workflow `depends_on` the prompt so a scheduled run cannot land between the two files and start an agent with nothing to execute. The prompt is read before the agent does anything, so its habit of checking out other branches cannot swap it mid-run.

**There are two prompt variants, and they differ only in their tail.** Both are the same document: two modes, sweep and repair, then the Part B sweep — bot PRs oldest first, repair the branch, read the Sonar gate from the API, wait on the final head commit, merge. The *releasing* variant (`mac-calendar-mcp`, `code-viewer-bot`) ends by writing a bump word and cutting one tag. The *publishing* variant (`kalpak44`, `bunker-party`, `mite-assistant-mcp`, `proklinator-app`, `noco-google-connector-web-page`) has no release step at all — those repos ship by publishing an image from main — and instead ends by acting on the image scan. Each variant is byte-identical across its repos apart from the banner, so a fix is a copy. Cross-references inside the prompt name Part B's sections rather than numbering them, because the two variants number everything past 19 differently and a stale number sends the agent to the wrong rules.

**A failed pipeline wakes the agent, and the trigger list is a union of names no single repo has.** `on.workflow_run.workflows` takes no wildcard, so every pipeline that may wake it has to be named — and the pipelines are not called the same thing everywhere (`Build, Publish, Deploy`, `Verify, Publish, Deploy`, `Release`). Listing all of them in every copy keeps the file byte-identical across its variant, because a name no workflow in that repo uses simply never matches. The agent's own workflow is deliberately absent: a failed repair must not trigger another one.

**`triage` is a separate job because it is both the cost brake and the loop brake.** Its job-level `if` drops anything that is not a `failure` or `timed_out` conclusion, so a green pipeline never starts a runner at all, and its one step exports the failed run's id, workflow, branch, commit and event for the prompt. The loop it prevents is real: the agent pushes with `GH_ADMIN_TOKEN`, so its own fixes start pipeline runs, and a fix that does not work would wake it for ever. It counts how many runs of that workflow have already failed on that commit — derived from the commit with `gh run list --commit`, never stored, so it cannot drift — and abandons the repair past `AI_MAX_FIX_ROUNDS` (3 unless the repo sets the variable). Its step writes each output key exactly once: a key written twice leaves the winner to the runner, and the one deciding whether the agent runs cannot be ambiguous.

**Repair mode may commit straight to the default branch, and local validation is the only thing standing in for CI.** A pipeline that failed on main has no pull request to repair and no check between the fix and what ships, so the prompt requires the repository's own build, lint, format and test commands to pass locally first, caps it at one commit per run, and prefers a revert when the right repair is not obvious. The wider rule is that the agent finishes the job rather than the run: it waits for the pipeline its fix started and confirms that what the pipeline exists to produce actually exists, because a run can conclude successfully with its publish step skipped by a condition. What it may *not* fix is anything it cannot reach — a missing or expired secret, or a bug in a workflow file, which is generated here and overwritten on the next apply. Those are reported and left, and working around one (moving a step off the credential, making it conditional) is explicitly out of bounds.

**The image scan needs the agent because it is deliberately non-blocking.** `--fail-on` is absent on purpose (an unfixable base-image CVE would deadlock the rollout), which means an unread report is the same as no report. The agent reads grype's findings from the latest successful *main* run — never from the pull request, because the scan job is gated on a published image and a PR has none — and fixes a finding only when grype names a fixed version that this repository can actually reach: a manifest dependency, or the base image tag. Anything with an empty `fix.versions`, or fixed only in a transitive package the repo does not pin, is reported and left. Suppression is not a fix: no grype ignore file, no `--fail-on` change, no dropped scan step.

**`SONAR_PROJECT_KEY` is not always the variable name.** `proklinator-app` analyses two projects and names them `SONAR_PROJECT_KEY_SITE` and `SONAR_PROJECT_KEY_API`, so an agent reading only `SONAR_PROJECT_KEY` there finds an empty string and silently skips the gate entirely. The prompt collects every non-empty key among the three and loops.

**A pre-existing gate failure is the agent's to fix, on the PR branch.** A prettier or eslint release that changes a default, or a new Sonar rule, fails code the bump never touched, and leaving it blocks that PR and every later one behind the same red gate. The limit is absolute and unchanged: fix the code, never the gate — no `eslint-disable`, no widened ignore file, no lowered threshold, no skipped test, no Sonar exclusion. Infrastructure stays out of scope, because a runner outage is not code and cannot be fixed on a branch. The agent reads the gate from SonarCloud's API rather than the CI log, because `sonar-scanner` exits 3 without naming a rule.

**`code-viewer-bot` carries three traps the other does not.** Its `npm ci` must pass `--ignore-scripts` in `verify`, because `robotjs` runs `node-gyp rebuild` at install time, needs X11 headers and does not build on Node 24 — `SKIP_ROBOTJS_REBUILD=1` skips only the *postinstall*. The tag-triggered build job does the opposite: it installs the X11 headers and rebuilds, because the packaged VSIX ships the native binding. `.prettierignore` must list `.github`, or prettier reformats the generated workflows, the next apply restores Terraform's copy, and `format:check` then fails on files no one can fix in the repo — blocking every merge. Its coverage thresholds are per-path with no `global` block, because Jest removes path-matched files from the global pool and a global floor would measure only the modules that require `vscode` or `robotjs` and cannot load outside a VS Code host. A fourth was fixed rather than documented: `.gitignore` contained `test/`, which held the whole suite out of git — the tests passed locally and CI reported `No tests found, exiting with code 1`.

**Exception — `deepaudit` keeps its `.github/` in the repo.** `terraform/github/deepaudit/` is the whole layer
dir: repo settings, the `DEEPSEEK_API_KEY` secret and the `DEEPSEEK_MODEL` variable, and no `github_repository_file`
at all. It has no PR agent, so the argument that put every other repo's workflows here — keeping the merge gate and
the thing that ships from drifting apart — buys nothing, and `audit.yml` is a manual workflow that takes a target
URL and two consent flags, which is a thing to edit next to the code it drives. The cost is real and is the reason
this is an exception rather than a new default: nothing stops a hand edit in the target repo, and its
`dependabot.yml` therefore *does* carry the `github-actions` ecosystem, which every generated-workflow repo has to
omit.

**The secret is `DEEPSEEK_API_KEY`, not `DEEPSEEK_APIKEY`.** The CLI and `audit.yml` read that spelling, and since
Terraform does not generate that workflow the repo's name is the one the secret has to match. It goes in the Actions
store only — the both-stores rule exists for agents running on Dependabot-triggered PRs, and nothing here reads the
key on such a run, so a Dependabot copy would be a credential with no reader.

**Exception — the container-image repos.** `kubectl-awscli` and `postgres-awscli` get `workflows/release.yml` instead
of `ai-maintenance-agent.yml`, and that file *is* their CI. It is one workflow, and now one **job**, because every step needs
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