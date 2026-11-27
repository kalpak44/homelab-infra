# 11. Managed repositories

Reference for Terraform-managed GitHub repositories and their application release agents.
These target-repository pipelines are separate from the homelab
[daily infrastructure agents](<9 - Daily maintenance agents.md>).

## Managed GitHub repos

`terraform/github/<repo>/` manages the settings of a GitHub repository and installs a DeepSeek-backed agent into it -
either the [PR agent](#what-the-agent-does) or, for the container-image repos, the [release agent](#release-agent).
One directory per repo, one R2 state file each (`homelab/github/<repo>.tfstate`) - same per-resource model as the other
layers.

| Repo                                      | Terraform dir                           | What it manages |
|-------------------------------------------|-----------------------------------------|------------------------------------------------------------------------------------|
| `kalpak44/bunker-party`                   | `github/bunker-party`                   | squash-only merges, `DEEPSEEK_APIKEY`, and **every workflow the repo has**: the AI maintenance agent (shared publishing variant — repairs the branch, reads the Sonar gate and the image scan, never tags), `publish.yml` (its CI *and* its PR check, which publishes `ghcr.io/kalpak44/bunker-party` and dispatches **GitOps - Bump images** for `bunker-game-app` to deploy it) and `dependabot.yml`. Also gets `GH_ADMIN_TOKEN` for that dispatch |
| `kalpak44/code-viewer-bot`                | `github/code-viewer-bot`                | same, plus **both workflows the repo has**: `release.yml` (its PR check and its publisher — `format:check`, `lint`, jest with per-path coverage floors and a waited-on SonarCloud gate; for a `v*` tag it also builds four platform VSIX files, cuts the GitHub release and publishes to the VS Code Marketplace) and `ai-maintenance-agent.yml`, identical to `mac-calendar-mcp`'s. Also gets `VSCE_PAT`, `GH_ADMIN_TOKEN` and `SONAR_TOKEN` in both secret stores |
| `kalpak44/deepaudit`                      | `github/deepaudit`                      | repo settings, `DEEPSEEK_API_KEY` and `DEEPSEEK_MODEL` - and nothing else. The repo owns its own `.github/`, so it gets no generated workflow and no PR agent: `ci.yml` and the manual `audit.yml` are edited in the repo itself |
| `kalpak44/forma-dsl`                      | `github/forma-dsl`                      | same, plus **all three workflows the repo has**: `release.yml` (its PR check and its publisher — `lint`, `typecheck`, the build across Node 20.19/22.13/24, coverage thresholds, the tarball-contents check and a waited-on SonarCloud gate; for a `v*` tag it publishes `forma-dsl` to npm through trusted publishing — no token — and cuts the GitHub release), `pages.yml` (the editor and reference docs to GitHub Pages) and `ai-maintenance-agent.yml`, identical to `mac-calendar-mcp`'s bar the manifest path. Also gets `GH_ADMIN_TOKEN` and `SONAR_TOKEN` in both secret stores |
| `kalpak44/jacred-tv-client`               | `github/jacred-tv-client`               | squash-only merges, `DEEPSEEK_APIKEY`, and **every workflow the repo has**: the AI maintenance agent (shared releasing variant - repairs the branch, merges bot PRs, cuts one tag per sweep) and `release.yml` (its PR check *and* its publisher - Gradle build with lint as the gate; for a `v*` tag it signs the APK with the key in `ANDROID_KEYSTORE_BASE64` and attaches it to the release), plus `dependabot.yml`. No SonarCloud: there is no test suite to measure. Also gets `GH_ADMIN_TOKEN` so the tag it cuts raises a run |
| `kalpak44/kalpak44`                       | `github/kalpak44`                       | squash-only merges, `DEEPSEEK_APIKEY`, and **every file the repo has under `.github/`**: the AI maintenance agent, `publish.yml` (its CI, which publishes `ghcr.io/kalpak44/kalpak44` and dispatches **GitOps - Bump images** for `personal-web-page` to deploy it) and `dependabot.yml`. Also gets `GH_ADMIN_TOKEN` for that dispatch |
| `kalpak44/kubectl-awscli`                 | `github/kubectl-awscli`                 | repo settings, `DEEPSEEK_APIKEY`, and the **release agent** workflow - not the PR agent |
| `kalpak44/mac-calendar-mcp`               | `github/mac-calendar-mcp`               | same, plus **both workflows the repo has**: `release.yml` (its PR check and its publisher — `format:check`, `lint`, jest at an 80% coverage threshold, the bundle build and a waited-on SonarCloud gate; releases only for a `v*` tag, carrying the zip) and `ai-maintenance-agent.yml`, which sweeps the bot PRs, repairs pre-existing gate failures on the branch, then cuts **one** tag for the whole sweep. Also gets `GH_ADMIN_TOKEN` (the tag push must start a run) and `SONAR_TOKEN` in both secret stores |
| `kalpak44/mite-assistant-mcp`             | `github/mite-assistant-mcp`             | same, plus `publish.yml` (its CI, its PR check, and its deploy trigger in one — `format:check`, `lint`, `npm test` at 80% coverage and a waited-on SonarCloud quality gate, then publishes `ghcr.io/kalpak44/mite-assistant-mcp`, scans it with syft + grype into the run summary as a report (0 Critical / 0 High since the move to `node:24-alpine`), and dispatches **GitOps - Bump images** for `mite-assistant-mcp`) and `dependabot.yml`, which proposes at 05:00 Europe/Sofia for the agent's 04:00 UTC sweep. Every merge in that sweep publishes its image but holds the rollout; the agent dispatches one rollout of the batch when it finishes. Also gets `GH_ADMIN_TOKEN` and `SONAR_TOKEN` (both secret stores) |
| `kalpak44/noco-google-connector-web-page` | `github/noco-google-connector-web-page` | same, plus `publish.yml` (its PR check, which validates `site/public` and deploys it to GitHub Pages from main) and the repo's Pages setting. No cluster deployment or DNS record |
| `kalpak44/postgres-awscli`                | `github/postgres-awscli`                | repo settings, `DEEPSEEK_APIKEY`, and the **release agent** workflow - not the PR agent |
| `kalpak44/proklinator-app`                | `github/proklinator-app`                | squash-only merges, `DEEPSEEK_APIKEY`, `SONAR_TOKEN`, and **all three workflows the repo has**: `publish.yml` (its CI *and* its PR check — format, lint, two vitest suites and two SonarCloud gates, then both `ghcr.io/kalpak44/proklinator-app` and `ghcr.io/kalpak44/proklinator-api` from one commit, a report-only image scan, and **GitOps - Bump images** for `proklinator`), `ai-issue-resolver-agent.yml` (implements an `ai:ready` issue, browser-tests it, opens a PR and merges it once green, capped by `AI_MAX_FIX_ROUNDS`) and `ai-maintenance-agent.yml` (sweeps the bot dependency PRs its `dependabot.yml` opens at 05:00 Sofia). Also gets `GH_ADMIN_TOKEN` for that dispatch |
| `kalpak44/song-radar`                     | `github/song-radar`                     | squash-only merges, `DEEPSEEK_APIKEY`, `SONAR_TOKEN`, and **every workflow the repo has**: the AI maintenance agent (shared publishing variant) and `publish.yml` (its CI *and* its PR check - `fmt:check`, `mvn verify` with JaCoCo and a waited-on SonarCloud gate, then `ghcr.io/kalpak44/song-radar` built by jib and a report-only syft/grype scan), plus `dependabot.yml` covering maven and npm. No cluster deploy yet |
| `kalpak44/workspaced-ai`                  | `github/workspaced-ai`                  | squash-only merges, `DEEPSEEK_APIKEY`, `SONAR_TOKEN` (both secret stores), and **every file under `.github/`**: the AI maintenance agent (shared publishing variant), `publish.yml` (its CI *and* its PR check - `fmt:check`, `mvn verify` with an 80% jacoco line floor and a waited-on SonarCloud gate, plus `apps/web` (React + Tailwind on Vite: vitest at an 80% line floor, its own waited-on SonarCloud gate `workspaced-ai-web`, type check, build), then `ghcr.io/kalpak44/workspaced-ai-api` (Spring Boot buildpacks, no Dockerfile), `ghcr.io/kalpak44/workspaced-ai-web`, `ghcr.io/kalpak44/workspaced-ai-site` (`apps/site`, the static public site at `workspaced.online`, link-checked) and `ghcr.io/kalpak44/workspaced-ai-harness` (opencode, the agent each workspace pod runs, smoke-tested locked down) from one commit, a report-only scan of each, and **GitOps - Bump images** for `workspaced-ai` to deploy the web app at `workspaced-ai.internal.pavel-usanli.online/` and the API under `/api/v1/`) and `dependabot.yml`. Created by Terraform rather than imported. Also gets `GH_ADMIN_TOKEN` so the agent's merges start a run |

**CI stays with the repo, mostly.** This layer ships the agent and points it at the repo's own check via the
`PR_CHECK_WORKFLOW` variable (`publish.yml` / `pr-check.yml`) - for most repos it does not manage the check itself. A
repo with no `pull_request` workflow will never have a green check, so the agent will never merge anything there.

Three repos are the exception. The two `*-awscli` container-image repos: their build workflow *is* managed here,
because the agent that bumps the tool versions and the workflow that publishes the resulting image are the same file -
see [Release agent](#release-agent) below. And `kalpak44/kalpak44`, whose `publish.yml` is both its CI and its cluster
deploy trigger; every file it has under `.github/` is generated from `github/kalpak44/` so the workflow and the
`gitops/Justfile` entry it has to agree with cannot drift apart.

Deploy: `just deploy github <repo>` (or the **GitHub - Deploy** workflow).

### What the agent does

Terraform pushes two files into the managed repo: `.github/workflows/ai-maintenance-agent.yml` and the prompt it runs,
`.github/agent-prompts/ai-maintenance-agent.md`. The workflow only decides whether there is work and hands the agent its
context; every policy decision is in the prompt.

It runs in **two modes**, decided by a short `triage` job before a runner is spent on the agent at all:

| Trigger | Mode | What it does |
|---|---|---|
| `schedule` daily 06:00 UTC, or `workflow_dispatch` | sweep | walks the open bot dependency PRs |
| `workflow_run` on a **failed** pipeline run | repair | fixes the cause and finishes what that run was doing |

**Sweep.** The agent installs the [Codex CLI](https://github.com/openai/codex), points it at DeepSeek, and hands it the
`gh` CLI plus the prompt. It then walks the open **bot-authored** PRs oldest first and, for each one in turn:

1. reads the diff and decides whether it is a safe dependency bump,
2. updates the branch if it is behind, and dispatches the repo's own `PR_CHECK_WORKFLOW` if the head commit has no
   checks (a PR opened before that workflow existed never gets one retroactively),
3. waits for every check to conclude,
4. merges with `gh pr merge --squash` **only** if all checks succeeded,
5. confirms the merge landed before moving to the next PR,
6. leaves a short comment explaining the decision.

It then reads the SonarCloud quality gate and the image scan on every sweep, including one that found no PR at all.

**Repair.** A failed run wakes the agent with that run's id, workflow, branch, commit and failure count. It reads the
failing step, classifies the cause — infrastructure, code, configuration or credential — and acts on the
classification: an infrastructure failure is re-run once and nothing is edited; a credential or workflow fault is
reported and left alone, because no commit here can fix either; a code fault is repaired on the PR branch when the
failure was on one, and directly on the default branch when it was not, with the repository's own validation run
locally first, since nothing else stands between that commit and what ships.

It finishes the job rather than the run: it waits for the pipeline its fix started, confirms what that pipeline was
supposed to produce actually exists, and — where the repo releases by tag — cuts the next version to complete a release
that failed, because the broken tag cannot be moved.

Human-authored PRs and branches are never touched. The merge policy lives in the prompt, not in bash.

**Why it cannot loop.** The agent pushes with a PAT, so its own fixes start pipeline runs, and a fix that does not work
would wake it again. `triage` counts how many runs of that workflow have already failed on that commit — derived from
the commit, never stored — and abandons the repair past `AI_MAX_FIX_ROUNDS` (3 by default). The agent's own workflow is
also absent from the `workflow_run` trigger list, so a failed repair cannot trigger another one.

**Why sequential.** Dependency PRs almost always touch the same lockfile. `gh pr merge --auto` arms them all at once and
they collide; merging one at a time means each PR rebases onto the previous merge instead of conflicting.

**Why no branch ruleset.** The agent is the gate - it refuses to merge without a green check. A ruleset was tried and
removed: its `pull_request` rule also blocks Terraform from committing the workflow files it manages
(`409 Changes must be made through a pull request`), which needs an admin bypass actor to work around.

**Wire protocol.** DeepSeek serves the OpenAI Responses API at `/v1/responses`, which is the only protocol Codex still
speaks - `wire_api = "chat"` was removed upstream. They talk directly, with no proxy in between.

**Both secret stores.** The key is written to the Actions *and* Dependabot stores. Runs triggered from a Dependabot PR
read from the Dependabot store, so a key present only in the Actions store would be empty on exactly the PRs that
matter.

### Release agent

`kubectl-awscli` and `postgres-awscli` are container-image repos rather than applications, so they get a different
agent. Terraform pushes `.github/workflows/release.yml` into each. It runs **weekly at 05:00 UTC on Mondays**
(`schedule`), on demand (`workflow_dispatch`, with `force_release` and `security_policy` inputs), and on every push to
`main`.

One job, because every step needs the tree the step before it produced, and because nothing reaches the registry until
the whole chain has passed:

```
resolve upstream (AI)  ->  build  ->  smoke  ->  scan  ->  remediate  ->  rescan
                                                                            |
                          publish  <-  commit  <-  version  <-  policy  <---+
```

**Resolve** - skipped on push. Codex + DeepSeek resolves the latest upstream releases (kubectl from
`dl.k8s.io/release/stable.txt`, Alpine from the Docker Hub tag list), edits the pins **in the Dockerfile itself**,
builds the result to prove it works, and prepends a `CHANGELOG.md` entry with a from/to table plus a short prose
paragraph. It writes `## vNEXT` - it does not pick the version number.

**Build, smoke, scan** - the candidate is built for amd64 with `--no-cache` and is **not pushed**. It must first pass
the compatibility contract: every binary the image promises, the real entrypoint, the uid, the TLS trust store, and -
for `postgres-awscli` - the MODE dispatch plus both scripts' refusal to run without their variables. Then syft + grype
scan it.

**Remediate** - see below. **Publish** - only after the policy gate; the multi-arch push reuses the amd64 layers from
the candidate build via the gha cache, so the bytes published are the bytes that were scanned.

**There is no versions file.** The Dockerfile is the source of truth for what goes in the image, and the newest
`## vX.Y.Z` heading in `CHANGELOG.md` is the version that gets tagged and published. Two files, both human-readable,
no third place to drift.

**The agent is not trusted.** Deterministic gates sit between it and the commit, all in bash:

| Gate | Catches |
|------------|---------------------------------------------------------------------------------------------|
| scope      | anything changed outside `Dockerfile` and `CHANGELOG.md`, or a missing `## vNEXT` heading    |
| provenance | a version that does not exist upstream, a package that does not resolve, a pin moving backwards, an exact `=version` apk pin |
| smoke      | a build whose tools, entrypoint, scripts or Python imports no longer work                    |
| policy     | an image measurably more vulnerable than the one already published                           |

The provenance gate is the important one: it re-resolves every pin against the registry and upstream independently of
the agent, so a hallucinated version cannot reach `main` even if the model is confident about it. The prompt says
"never guess"; the gate is what makes that true.

**Why one job and not two.** A push made with `GITHUB_TOKEN` does not trigger another workflow run, so the agent's bump
commit cannot re-fire `on: push`. Everything happens in one run, and one commit carries the whole result.

**The build and scan run every week**, even when no version moved. A quiet week still refreshes the vulnerability
report and the SARIF upload; it just does not publish.

#### Security policy

Critical and High are acted on. A finding is **fixable** when grype knows a fixed version exists; **unfixable** when
there is no upstream fix at all. A third case is reported separately and matters most in practice: a fix exists
upstream but Alpine has not packaged it yet, so nothing the pipeline can do will reach it.

When any Critical/High remains, remediation is attempted. Each attempt is built, smoke-tested and rescanned, and is
kept **only** if Criticals do not rise, Critical+High strictly falls, every smoke check still passes, and no shipped
tool's major version moved. Otherwise it is reverted whole. Levers: move the Alpine tag (newest first), move kubectl to
current stable, drop a genuinely unneeded package - then one AI round that may propose one more minimal change through
the identical gate.

Publication is decided against the image on `:latest`, **rescanned in the same run with the same grype database** so
the comparison reflects the change rather than a week of database growth:

| `security_policy` | Behaviour |
|-------------------|-----------|
| `enforce` (default) | Block if the candidate has more Criticals, or more Critical+High, than the published image. Findings remediation could not reach do **not** block - refusing to publish would pin consumers to an older image with the same CVEs *plus* the ones already fixed. |
| `strict`            | Additionally block while any fixable Critical/High remains. |
| `report-only`       | Never block. Break-glass, for shipping a rebuild while a scanner or feed problem is sorted out. |

What is deliberately **not** done, because it trades a working image for a green scanner: exact `=version` apk pins,
`edge`/`testing` repositories, pip-installing over the Python libraries Alpine's `aws-cli` package owns, and moving the
PostgreSQL client major (`pg_dump` refuses to read a newer server).

`apk upgrade` is **not** a lever and must not be re-added: it was measured on both images and changes nothing, because
the official `alpine:X.Y` tag already carries the newest patch level and `apk add --no-cache` already fetches current
packages.

The base bump is also **not** a blind `+1`. On `kubectl-awscli`, stepping 3.22 → 3.23 raised Criticals from 8 to 10
while 3.22 → 3.24 cut them to 2; a one-step loop would propose the regression, measure it, revert, and repeat for ever.
The search walks candidate tags newest-first, which is safe precisely because each one is built, smoke-tested and
rescanned before it is kept.

#### Versioning

Releases follow SemVer, and the workflow - not the agent - computes the number from what actually changed between the
published image and the candidate:

| Observed change | Level |
|-----------------|-------|
| a shipped tool's **major** moved, an apk package was dropped, or entrypoint/command/user/workdir changed | breaking |
| the Alpine minor moved, or a shipped tool's **minor** moved | feature |
| anything else that changes the image - tool patch levels, package revisions, a security remediation | fix |

Mapped to a component, honouring SemVer's pre-1.0 clause (§4 - anything may change in `0.y.z`):

| | `0.y.z` | `1.y.z` and up |
|---|---|---|
| breaking | minor | major |
| feature | minor | minor |
| fix | patch | patch |

Previous tool versions come from the `io.homelab.tools.*` labels the last release wrote onto `:latest`, so the
comparison is against what was really published. A PostgreSQL client major move therefore lands as a minor bump today
and as a major bump once the image reaches 1.0.0.

**Pinned vs recorded.** Only what can be reliably pinned is pinned: the Alpine tag, and `KUBECTL_VERSION` in
`kubectl-awscli` (dl.k8s.io keeps every release). Everything from the Alpine package repo - the PostgreSQL client, the
MinIO client, jq, curl - is installed *unversioned*, because an exact `=version` apk pin breaks the moment Alpine drops
that package, and `postgresql-client` without a number resolves to whichever major the release ships. Their versions
are read back out of the built image and recorded in the labels and release notes instead. Bumping the Alpine tag is
what moves them.

**`kubectl-awscli` no longer ships the AWS CLI.** On Alpine it is the Python build, and it brought a Python runtime
plus about sixty packages with it - which was every Critical and all but one High finding the image had, none of them
with a fixed version Alpine had packaged. Dropping it took the image from 65 MB to 25 MB and left one unfixable `zlib`
High. `postgres-awscli` keeps it: swapping in a Go S3 client was tried and reverted, because grype catalogs a Go
binary's vendored modules and `minio-client` scans as 8 Critical against the AWS CLI's 2.

**`postgres-awscli`'s gate runs a real round trip.** The smoke suite starts a PostgreSQL and a MinIO container, takes a
backup, drops the table, restores it, checks the row count, and then runs a second backup with `RETENTION_COUNT=1` to
prove the retention policy prunes. Every remediation attempt re-runs it, so a change that clears a CVE and breaks the
backup is rejected rather than published.

### `GH_ADMIN_TOKEN` scopes

The built-in `GITHUB_TOKEN` cannot manage other repositories, so this layer needs its own PAT:

| PAT type    | Required                                                                              |
|-------------|---------------------------------------------------------------------------------------|
| Classic     | `repo` + `workflow`                                                                   |
| Fine-grained | Administration, Contents, Secrets, Dependabot secrets, Variables, Workflows - all *write* |

> `terraform destroy` on this layer removes the secrets, the agent workflow file and any ruleset. The repository itself
> is **archived, not deleted** (`archive_on_destroy = true`).

---
