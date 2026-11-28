# Nix CI

The target architecture for CI in every Nix repo Erik owns, now or later.
It was worked out on the map [Get Nix CI into a clean state](https://github.com/UnstoppableMango/nixos/issues/497); each section links the ticket that decided it, and that ticket holds the reasoning.
This document states what the system is meant to be.
The build tickets in [Migration](#migration) get it there.

## What "clean" means

Each Destination criterion has one owner: the component that makes it true.

| Criterion | Owner | Measured by |
| --- | --- | --- |
| `main` is green in every repo | The [`required` gate](#the-required-gate-and-rulesets), with [upstream breakage](#upstream-breakage) handled by the exclude and nightly lists | The daily [CI health](#observability) workflow |
| Routine Renovate bumps merge untouched, hash and lock refreshes included | The [Renovate presets](#renovate) and the [fixup job](#renovate-fixup); [`update.sh`](#package-collections) in collection repos | `renovate:needs-human` count in the CI health issue |
| A warm no-op run takes under 5 minutes | The persistent [builder store](#builder-vm) for Hercules repos; [drv-diff builds](#package-collections) and Cachix for collections | p50 and p90 of the `required` job's duration on `main`, per repo |
| No host's OS disk fills up for 30 days | Store and cache on their own [disk](#hardware), [builder GC](#builder-store-gc), the weekly `nh clean` on clan machines | Disk pushes to [Gatus](#observability), 30 days of history |
| No container starts with an empty store | ARC is retired for Nix jobs; the [builder VM](#builder-vm) keeps its store; hosted jobs read [Cachix](#binary-caches) | Gate durations |
| A new Nix repo joins through shared pieces only | [`flakeModules.ci`](#the-flake-module), the [`unmango/ci`](#reusable-workflows) workflows, the [`nix-ci` preset](#renovate) | The "How to join CI" checklist in the `UnstoppableMango/nix` README |

"Green" means the `required` gate and Hercules on `main`.
Deploy jobs sit outside the gate and don't count, though they still alert ([#513](https://github.com/UnstoppableMango/nixos/issues/513)).

## Trust model

Decided in [Choose the isolation model for on-prem builds](https://github.com/UnstoppableMango/nixos/issues/503).

- Only Erik's own commits and his bots (Renovate, release-please, thecluster[bot]) run on-prem.
  Fork PRs and third-party code run only on GitHub-hosted runners.
- Everything on-prem is one trust domain, so PR and `main` builds share one store.
- The threat the boundary answers is a build getting root on a bare-metal host.
  The boundary is a VM with its own kernel, never a shared kernel and a shared store.
- The host's `/nix` is never mounted into a VM or container.
  Anything shared across the boundary is read-only and signature-checked.
- Each cache has one writer and one signing key, and no signing key lives inside the builder VM.
  Only CI on `main` writes to a cache; that part is a convention, not a boundary, since PR and `main` share a trust domain.
- Recovery from a suspected compromise is rebuilding the builder store and the attic cache from empty, by hand.

There are no `checks.*` assertions for these rules.

## Hardware

Decided in [Plan the migration order and cutover](https://github.com/UnstoppableMango/nixos/issues/510) and [Decide builder store GC and the disk split](https://github.com/UnstoppableMango/nixos/issues/511).

- gaea hosts the builder VM and the attic VM.
  A WD SN7100 2 TB on a PCIe adapter holds an LVM volume group: 1.2 TB for the builder store, 400 GB for attic, about 260 GB unallocated as growth and wear headroom.
  Each logical volume is its VM's own virtio disk.
- gaea's OS disk is a WD SN850 1 TB (0% wear at install), replacing the worn SN750.
- zeus's worn 850 EVO is replaced with the drive on hand; zeus leaves CI.
  It can host a second builder VM later if the load needs one.
- hades leaves CI entirely.

## Builder VM

Decided in [#503](https://github.com/UnstoppableMango/nixos/issues/503) and [Choose which system runs Nix CI](https://github.com/UnstoppableMango/nixos/issues/505).

- One long-lived microVM per builder host, gaea first, built with microvm.nix on cloud-hypervisor, nested virtualisation off, no virtiofs.
- Its store is persistent, on the 1.2 TB logical volume, and shared by PR and `main` builds.
- It runs one Hercules CI agent per account (`unmango`, `unstoppablemango`) beside its own nix-daemon.
  The host runs nothing for CI but the VMM.
- Network: an isolated bridge with NAT to the internet.
  The only LAN destination it can reach is the attic VM; not the host, the clan machines, rosequartz or the management network.
- Substituters: attic, cache.nixos.org and nix-community, with `fallback = true`.
- It holds attic's push-only token and no signing key.
- Nix's own auto-GC (`nix.gc`, `min-free`, `max-free`) is off inside it, because the agent holds no GC roots for running tasks (see [Builder store GC](#builder-store-gc)).

### Builder store GC

Decided in [#511](https://github.com/UnstoppableMango/nixos/issues/511).

- An hourly check on the store volume.
  Below 15% free, it stops the agents, runs `nix store gc --max <bytes>`, with `<bytes>` the amount that brings the volume to 35% free, and starts the agents again, interrupting any running task.
- Nothing is rooted.
  A "root keeper" for each repo's latest green `main` is held in reserve, built only if random eviction shows up as slow runs.
- Each run pushes its result to Gatus; a collection that can't reach 35% pages.

## Binary caches

Decided in [Choose the binary cache layout](https://github.com/UnstoppableMango/nixos/issues/504) and [Decide how the LAN shares deploy closures without harmonia](https://github.com/UnstoppableMango/nixos/issues/512).

- **attic**, in its own microVM on gaea, on the 400 GB logical volume.
  The attic server holds the signing key; CI pushes with a push-only token, from `main` only.
  Paths are kept 90 days after last access, with attic's default 12-hour GC.
- **Cachix `unstoppablemango`**, the free tier, serves jobs off the LAN (hosted runners).
  Only `main` CI writes to it.
  `mangopkgs` and `unmango` are merged into it and retired.
  If 5 GB proves too small, the next step is exposing attic or backing it with R2.
- **Clan machines** substitute from attic, cache.nixos.org and nix-community, plus nixos-raspberrypi on gaea and the Pis, with `fallback = true`.
- **Nothing serves host stores to the LAN.**
  Each x86 host pulls upstream paths itself, and the Pis get theirs from gaea through `build-host`.
  If bandwidth ever matters, the fallback is an nginx pull-through cache of upstream in the attic VM, with no new key.

## CI systems

Decided in [#505](https://github.com/UnstoppableMango/nixos/issues/505) and [Decide how package-collection repos run CI and updates](https://github.com/UnstoppableMango/nixos/issues/514).

| Job | Runs on |
| --- | --- |
| x86_64-linux checks and packages of a public application repo, branch PRs and `main` | Hercules agents in the builder VM |
| Fork PRs | Hosted `nix flake check`, after workflow approval, reading Cachix and never pushing |
| darwin | Hosted `macos-latest`, only in repos that build for darwin |
| aarch64-linux | Hosted `ubuntu-24.04-arm` |
| Private repos and repos in other accounts | Hosted only |
| Release and deploy jobs needing GitHub OIDC | Hosted |
| Package-collection repos | Hosted only (see [Package collections](#package-collections)) |

nixbot is the planned later replacement for Hercules once it has tagged releases and a stable stretch.
It reads `herculesCI` unchanged, so the swap touches no repo.

During a Hercules outage the gate keeps waiting, Renovate automerge waits with it, the admin bypass covers urgent merges, and Gatus pages.

## The `required` gate and rulesets

Decided in [Decide required checks and rulesets per repo](https://github.com/UnstoppableMango/nixos/issues/509).

- Every Nix repo's `main` ruleset requires exactly one check: `required`, a hosted job (app 15368).
  A repo decides what blocks a merge by editing the gate's `needs`, never its ruleset.
- The gate needs every hosted job that runs on pull requests, and no release or deploy job.
- On a branch PR it waits, up to 6 hours, for `ci/hercules/onPush/default` on the head commit, and passes only when it is green and was posted by the Hercules app (24794).
- On a fork PR it runs the Linux `nix flake check` itself on a hosted runner.
- Every repo requires approval before running workflows from outside collaborators.
- Repository admins can bypass in `pull_request` mode; this is a default of the `main` ruleset in both the scm and vcs `PublicRepo` components.
- No merge queue and no up-to-date requirement for now.

## Shared pieces

Decided in [Decide what a Nix repo adds to join CI](https://github.com/UnstoppableMango/nixos/issues/508), amended by [#514](https://github.com/UnstoppableMango/nixos/issues/514).

### The flake module

`flakeModules.ci` in `UnstoppableMango/nix`, pinned through `flake.lock`:

- Sets `herculesCI` with `ciSystems = [ "x86_64-linux" ]`; `onPush.default` builds checks and packages.
- An exclude list drops outputs from the default.
  A nightly list moves outputs, such as devShells or packages that keep breaking upstream, to `onSchedule`, built but not gating.
- Provides `apps.<system>.renovate-fixup` from the refresh steps the repo declares (gomod2nix, `npmDepsHash`, `make generate`, and so on); with none declared it does nothing.

Every template in `UnstoppableMango/nix` imports the module and ships a `ci.yml`.

### Reusable workflows

`unmango/ci` holds every reusable CI workflow; repos pin them by SHA.
`unmango/actions` keeps composite actions such as `setup-nix`.

- `nix-ci.yml`: the hosted jobs and the `required` gate, with switches for `darwin`, `aarch64-linux`, `linux` (private repos) and `cachix-push` (on `main` only, with a per-repo `CACHIX_AUTH_TOKEN`), plus the [`renovate-resume`](#resuming-after-a-red-main) job.
- `renovate-fixup.yml`: see [Renovate fixup](#renovate-fixup).
- `collection-ci.yml` and `package-updates.yml`: see [Package collections](#package-collections).
- `ci-health.yml`: see [Observability](#observability).

### Joining CI

A new repo starts from a template, or adds the input and module, adds `ci.yml` with its `ci-health` job, extends `renovate-config:nix-ci` (and `deploys` if its `main` deploys), adds its ruleset entry in scm or vcs, and sets `CACHIX_AUTH_TOKEN`.
The checklist lives in the `UnstoppableMango/nix` README.
Private repos, repos in other accounts and repos without a flake join hosted-only with `linux: true`.
Hosted runners bill minutes on private repos, so a private repo's gate runs on `pull_request` only, skipping docs-only changes, and nothing hosted runs on pushes to `main` except its deploys.

## Renovate

Decided in [Decide the Renovate update policy](https://github.com/UnstoppableMango/nixos/issues/506), [#508](https://github.com/UnstoppableMango/nixos/issues/508) and [Decide how upstream breakage on main gets handled](https://github.com/UnstoppableMango/nixos/issues/513).

The `renovate-config:nix-ci` preset, extended after the default (which stays as it is for non-Nix repos):

- Four groups: `flake.lock` maintenance, all other lock file maintenance, all non-major updates, each major on its own.
- One window for all of them: Monday before 6 AM, America/Chicago.
  `minimumReleaseAge: 3 days` except security fixes; `vulnerabilityAlerts` skip the schedule.
- `rebaseWhen: conflicted`.
- Automerge through `platformAutomerge` for everything but majors, which wait for Erik.
- The `renovate-fixup` App's bot email in `gitIgnoredAuthors`, and `renovate:needs-human` as `stopUpdatingLabel`.

The `deploys` preset turns automerge off for updates that deploy, in repos whose `main` deploys (the-cluster, vcs, scm, control-plane); they still automerge `flake.lock`, Actions pins and dev tooling.
It replaces the old opt-in `automerge` preset, and the per-repo monthly schedules go.

Fixes that need no build run in the Renovate pod as post-upgrade tasks (gomod2nix, nuget2nix, source prefetches, the-cluster's hash scripts, `nix flake update`).
The pod never builds and has no real store.
`allowedCommands` match in both Renovate HelmReleases.

### Renovate fixup

Fixes that need a build run in `renovate-fixup.yml` on `renovate/**` pushes, on hosted runners:

1. A credential-less job runs `nix run .#renovate-fixup` and uploads a patch.
2. A second job mints a token for the contents-only `renovate-fixup` App, applies the patch, and pushes to that branch only.

The builder VM never holds a push token.
If the fixup fails, nothing is pushed and the workflow labels the PR `renovate:needs-human`, unless `main`'s latest gate is red, in which case it leaves the label off.
A labelled PR never retries; Erik fixes the branch or closes the PR.

### Resuming after a red `main`

Decided in [#538](https://github.com/UnstoppableMango/nixos/issues/538).

With `rebaseWhen: conflicted` a clean branch is never pushed again, and GitHub never reruns a PR's checks when `main` changes.
A Renovate PR whose fixup or gate failed while `main` was red would stall.
`nix-ci.yml` and `collection-ci.yml` carry a `renovate-resume` job for it:

- It runs on a push to `main` after the gate passes, and only when the previous completed `required` run on `main` failed.
- It ticks Renovate's rebase checkbox on every open Renovate PR whose head's latest `required` result is a failure and that isn't labelled `renovate:needs-human`.
  Renovate rebases them onto the fixed `main`, and that push reruns the fixup and the gate.
- It uses the workflow's `GITHUB_TOKEN` with `pull-requests: write`.

A PR whose fixup fails again gets `renovate:needs-human`, since `main` is now green.
A PR whose fixup passes but whose gate stays red gets no label.
Waiting PRs carry no label: a red `main` already pages after 24 hours.

## Package collections

Decided in [#514](https://github.com/UnstoppableMango/nixos/issues/514).

unmango/pkgs, unmango/pulumipkgs and unmango/kubepkgs run on hosted GitHub Actions only, cached in Cachix.
UnstoppableMango/nix is an application repo, not a collection.

- `collection-ci.yml` evaluates base and head with `nix-eval-jobs` and builds only the outputs whose `.drv` changed, on x86_64-linux, aarch64-linux and aarch64-darwin, on PRs and `main`.
  The `required` gate aggregates the matrix.
  A weekly scheduled full build keeps the cache warm.
  Only package outputs from `main` are pushed.
- `package-updates.yml` runs each repo's own "list candidates and bump one package" script weekly, Friday after 6 PM Chicago, with a 3-day minimum release age where the upstream date is readable.
  Each package has one branch, `update/<name>`, force-pushed when a newer version appears.
  Package failures are rewritten into one pinned "package update failures" issue; a package PR that can't build gets `renovate:needs-human`; the run itself fails only when the script breaks.
  It authenticates as the `package-updates` App (contents and pull-requests write, installed on collection repos only), keeping API-signed commits.
- Renovate keeps the lock files.

## Upstream breakage

Decided in [#513](https://github.com/UnstoppableMango/nixos/issues/513).

Since `flake.lock` only changes through a gated PR, upstream breakage reaches `main` only through an admin bypass, a source that vanishes or is re-tagged after merge, or a deploy job.

- A package broken upstream goes on the `flakeModules.ci` exclude list in a one-line PR, with an issue tracking it.
- One that keeps breaking moves to the nightly list.
- Generated-file drift after a lock bump is a declared fixup step.
- Vanished sources get no new machinery; attic's retention covers the gap until a rebuild is needed.

## Observability

Decided in [Decide how we know CI meets the Destination](https://github.com/UnstoppableMango/nixos/issues/515).

- **Gatus on pik8s3**, outside rosequartz, is the hub for infra checks and keeps 30 days of history.
- Every clan machine (through the `base` instance) and the builder and attic VMs push disk status to Gatus external endpoints on a timer.
  The builder's GC and agent liveness push the same way.
  A missed push is a failure.
- **Pages** go to ntfy.sh on a long random topic kept as a clan var, to Erik only, with no secrets in the text: any OS disk under 10% free, a builder GC that misses its target, the builder VM or its agents down, attic down or under 15% free, a Hercules outage, and a `main` red for more than 24 hours.
- **`ci-health.yml`** in `unmango/ci` is a reusable workflow each Nix repo calls from its own `ci-health` job, daily and on push to `main`.
  It keeps a pinned "CI health" issue labelled `ci-health` in the calling repo, written with that repo's `GITHUB_TOKEN`: its `main`, open `renovate:needs-human` PRs, and p50 and p90 of the `required` run's duration on `main`, flagging a p50 over 5 minutes.
  A red `main` carries the `ci-health:red` label, and the body records when the streak started.
  Decided in [Decide the shape and language of the CI health workflow](https://github.com/UnstoppableMango/nixos/issues/548).
- **The aggregator** in `UnstoppableMango/nix` runs hourly, finds the `ci-health` issues with one search across both accounts, and keeps a pinned "Nix CI health" issue in that repo listing every repo.
  Its own issue carries no `ci-health` label, so neither workflow touches the other's issue in `UnstoppableMango/nix`.
  It leaves out private repos, since its issue is public; their own `ci-health` issues still report on them, but they do not page.
  It pages in the hour a `main` passes 24 hours red and every 24 hours after that, read from the streak's age alone.
  A streak that passes 24 hours and clears before the next aggregator run may not page, since by then there is nothing left to fix.
  The weekly digest holds whatever the current issues show that isn't a page.
  The ntfy topic is a secret in that repo alone.
- Both keep custom code small: `run:` steps with `gh` and `jq`, and `actions/github-script` only where JS is really needed.
- The in-cluster Alertmanager is outside this design.

## Removed

| Piece | Why |
| --- | --- |
| Bare-metal Hercules agents (hades, zeus, gaea) | A sandbox escape gets root on the host |
| ARC scale sets for Nix jobs, and `modules/arc-runner-store` | Shared kernel, and every job starts with an empty store |
| ncps | Runners have a warm store; attic replaces it |
| harmonia on every host | It signs whatever is in the host store, PR output included |
| `mangopkgs` and `unmango` Cachix caches | Merged into `unstoppablemango` |
| The `automerge` Renovate preset and per-repo monthly schedules | Replaced by `nix-ci` |
| Erik's PAT in collection update workflows | Replaced by the `package-updates` App |

## Migration

The order is from [#510](https://github.com/UnstoppableMango/nixos/issues/510).
Each step is a build ticket in the repo that owns it, and each ticket names its blockers.

0. **Wave 0:** hades and zeus leave Hercules and harmonia, the harmonia key is rotated, zeus's OS drive is swapped.
1. **gaea maintenance window:** the SN7100 and the new OS disk go in together.
2. **Shared pieces**, in parallel with 1, 3 and 4: `unmango/ci`, `flakeModules.ci`, the workflows, the presets, the Apps, the ruleset defaults, alerting.
3. **attic VM**, empty.
4. **Builder VM** with GC; gaea's bare-metal agents drop to 0 tasks but stay defined.
5. **Proof:** every task in the VM, warm no-op under 5 minutes on tdl, no VM-caused failures, every GC reaches its target.
   Then the bare-metal agents go.
6. **Clan substituter switch**, gaea first: attic in, ncps and harmonia out of the clan.
   The ncps deployment itself stays until ARC stops running Nix jobs.
7. **Repo waves**, each repo in three merges (add the gate, switch the ruleset once Hercules is green on `main`, drop the hosted Linux check), with ruleset switches batched per wave: wave 1 nix and nixos; wave 2 tdl, the-cluster, vcs, control-plane, renovate-config; wave 3 scm, charts, and the collections; wave 4 the repos whose CI still runs on the `thecluster` ARC runners (thecluster-operator, dotfiles, johnston-dems-mailer, iam, thecluster.lan, lang, architecture, go, go-fp, tfpkgs and enclave); wave 5 every other Nix repo.
   Wave 4 runs alongside wave 3, since it is what lets step 8 retire ARC for Nix jobs.
   In waves 4 and 5 a public repo's job that runs through `nix develop` becomes a flake check where it can, so Hercules builds it, and one that needs a container runtime moves to a hosted runner.
   A job that must reach the LAN, such as iam's Pulumi run against in-cluster Keycloak, stays on ARC without Nix.
8. **Cleanup:** ncps, ARC scale sets for Nix jobs and the runner store module after wave 4, then the old Cachix caches 30 days after wave 5, since wave 5 repos still substitute from `mangopkgs`.

### Build tickets

Each ticket names its blockers in a `Blocked by:` line.
Tickets for `unmango/ci` are filed in nixos until that repo exists, and the kubepkgs ticket is filed in nixos too.

| Step | Ticket |
| --- | --- |
| 0 | [Take hades and zeus out of Hercules CI and rotate the harmonia key](https://github.com/UnstoppableMango/nixos/issues/518) |
| 0 | [Replace zeus's worn OS drive](https://github.com/UnstoppableMango/nixos/issues/522) |
| 1 | [Fit the SN7100 and swap gaea's OS disk in one maintenance window](https://github.com/UnstoppableMango/nixos/issues/519) |
| 2 | [Add the unmango/ci repository](https://github.com/unmango/scm/issues/373) |
| 2 | [Create the renovate-fixup and package-updates GitHub Apps](https://github.com/UnstoppableMango/nixos/issues/520) |
| 2 | [Add flakeModules.ci](https://github.com/UnstoppableMango/nix/issues/151) |
| 2 | [unmango/ci: add nix-ci.yml with the required gate](https://github.com/unmango/ci/issues/1) |
| 2 | [unmango/ci: add renovate-fixup.yml](https://github.com/unmango/ci/issues/5) |
| 2 | [Add the nix-ci and deploys presets](https://github.com/UnstoppableMango/renovate-config/issues/67) |
| 2 | [Match allowedCommands in both Renovate HelmReleases for no-build fixes](https://github.com/UnstoppableMango/the-cluster/issues/4952) |
| 2 | [Ship flakeModules.ci in every template and document how to join CI](https://github.com/UnstoppableMango/nix/issues/152) |
| 2 | [Give PublicRepo the gate-only ruleset shape (vcs)](https://github.com/UnstoppableMango/vcs/issues/159) |
| 2 | [Give PublicRepo the gate-only ruleset shape (scm)](https://github.com/unmango/scm/issues/374) |
| 2 | [Page through Gatus and ntfy, with disk pushes from every clan machine](https://github.com/UnstoppableMango/nixos/issues/521) |
| 2 | [Add the reusable CI health workflow](https://github.com/unmango/ci/issues/2) |
| 2 | [Add the CI health aggregator workflow](https://github.com/UnstoppableMango/nix/issues/158) |
| 2 | [unmango/ci: add collection-ci.yml with drv-diff builds](https://github.com/unmango/ci/issues/3) |
| 2 | [unmango/ci: add package-updates.yml](https://github.com/unmango/ci/issues/4) |
| 3 | [Run attic in a cache microVM on gaea](https://github.com/UnstoppableMango/nixos/issues/524) |
| 4 | [Run the builder microVM on gaea with a Hercules agent per account](https://github.com/UnstoppableMango/nixos/issues/529) |
| 4 | [Add builder store GC and move gaea's CI into the VM](https://github.com/UnstoppableMango/nixos/issues/530) |
| 5 | [Remove gaea's bare-metal Hercules agents after the proof](https://github.com/UnstoppableMango/nixos/issues/531) |
| 6 | [Switch the clan's substituters to attic and remove harmonia and ncps](https://github.com/UnstoppableMango/nixos/issues/532) |
| 7, wave 1 | [Move nix onto the required gate](https://github.com/UnstoppableMango/nix/issues/153) |
| 7, wave 1 | [Move nixos onto the required gate](https://github.com/UnstoppableMango/nixos/issues/533) |
| 7, wave 1 | [Switch wave 1 rulesets to the required gate](https://github.com/UnstoppableMango/vcs/issues/160) |
| 7, wave 2 | [Move tdl onto the shared CI pieces and the required gate](https://github.com/UnstoppableMango/tdl/issues/1593) |
| 7, wave 2 | [Move the-cluster onto the shared CI pieces and the required gate](https://github.com/UnstoppableMango/the-cluster/issues/4953) |
| 7, wave 2 | [Move vcs onto the shared CI pieces and the required gate](https://github.com/UnstoppableMango/vcs/issues/161) |
| 7, wave 2 | [Move control-plane onto the shared CI pieces, hosted-only](https://github.com/UnstoppableMango/control-plane/issues/55) |
| 7, wave 2 | [Move renovate-config onto the shared CI pieces and the required gate](https://github.com/UnstoppableMango/renovate-config/issues/68) |
| 7, wave 2 | [Switch wave 2 rulesets to the required gate](https://github.com/UnstoppableMango/vcs/issues/162) |
| 7, wave 3 | [Move scm onto the shared CI pieces and the required gate](https://github.com/unmango/scm/issues/375) |
| 7, wave 3 | [Move charts onto the shared CI pieces and the required gate](https://github.com/unmango/charts/issues/149) |
| 7, wave 3 | [Move pkgs onto collection CI and weekly package updates](https://github.com/unmango/pkgs/issues/218) |
| 7, wave 3 | [Move pulumipkgs onto collection CI and weekly package updates](https://github.com/unmango/pulumipkgs/issues/129) |
| 7, wave 3 | [kubepkgs: move onto collection CI and weekly package updates](https://github.com/UnstoppableMango/nixos/issues/534) |
| 7, wave 3 | [Switch wave 3 rulesets to the required gate](https://github.com/unmango/scm/issues/376) |
| 7, wave 4 | [Move thecluster-operator onto the shared CI pieces and the required gate](https://github.com/unmango/thecluster-operator/issues/177) |
| 7, wave 4 | [Move dotfiles onto the shared CI pieces and the required gate](https://github.com/UnstoppableMango/dotfiles/issues/242) |
| 7, wave 4 | [Move johnston-dems-mailer onto the shared CI pieces, hosted-only](https://github.com/UnstoppableMango/johnston-dems-mailer/issues/409) |
| 7, wave 4 | [Move iam onto the shared CI pieces, hosted-only](https://github.com/UnstoppableMango/iam/issues/13) |
| 7, wave 4 | [Move thecluster.lan onto the shared CI pieces and the required gate](https://github.com/UnstoppableMango/thecluster.lan/issues/64) |
| 7, wave 4 | [Move lang onto the shared CI pieces and the required gate](https://github.com/UnstoppableMango/lang/issues/176) |
| 7, wave 4 | [Move architecture onto the shared CI pieces, hosted-only](https://github.com/unmango/architecture/issues/73) |
| 7, wave 4 | [Move go onto the shared CI pieces and the required gate](https://github.com/unmango/go/issues/210) |
| 7, wave 4 | [Move go-fp onto the shared CI pieces and the required gate](https://github.com/unmango/go-fp/issues/14) |
| 7, wave 4 | [Move tfpkgs onto collection CI](https://github.com/unmango/tfpkgs/issues/24) |
| 7, wave 4 | [Move enclave onto the shared CI pieces and the required gate](https://github.com/unmango/enclave/issues/34) |
| 7, wave 4 | [Switch wave 4 rulesets to the required gate (vcs)](https://github.com/UnstoppableMango/vcs/issues/175) |
| 7, wave 4 | [Switch wave 4 rulesets to the required gate (scm)](https://github.com/unmango/scm/issues/397) |
| 7, wave 5 | [Move pki onto the shared CI pieces, hosted-only](https://github.com/UnstoppableMango/pki/issues/336) |
| 7, wave 5 | [Move azure onto the shared CI pieces, hosted-only](https://github.com/UnstoppableMango/azure/issues/20) |
| 7, wave 5 | [Move pfsense onto the shared CI pieces, hosted-only](https://github.com/UnstoppableMango/pfsense/issues/15) |
| 7, wave 5 | [Move the remaining public Nix repos onto the shared CI pieces](https://github.com/UnstoppableMango/nixos/issues/576) |
| 7, wave 5 | [Switch wave 5 rulesets to the required gate (vcs)](https://github.com/UnstoppableMango/vcs/issues/176) |
| 7, wave 5 | [Switch wave 5 rulesets to the required gate (scm)](https://github.com/unmango/scm/issues/398) |
| 8 | [Remove ncps and the ARC runners that only served Nix jobs](https://github.com/UnstoppableMango/the-cluster/issues/4954) |
| 8 | [Remove the ARC runner store module](https://github.com/UnstoppableMango/nixos/issues/535) |
| 8 | [Delete the mangopkgs and unmango Cachix caches](https://github.com/UnstoppableMango/nixos/issues/536) |
