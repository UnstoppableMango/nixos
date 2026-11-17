# Renovate updates that fix Nix hashes themselves

Research for UnstoppableMango/nixos#501 (part of #497). Researched 2026-11-17 against primary sources: Renovate's source and docs on `main` of renovatebot/renovate, containerbase's source, nix-update's source, the nixpkgs manual, GitHub's docs, the deployed config in the-cluster, and real PRs and CI logs in the repos. Every claim cites its source.
Where a claim is my inference rather than something a source states, it says so.

Caveats on sources:

- **`UnstoppableMango/renovate-config` could not be read.** The GitHub MCP tool refused it ("repository ... is not configured for this session"). What this note says about the `gomod2nix` and `nuget2nix` presets comes from the `allowedCommands` patterns that admit them, the consuming `.github/renovate.json` files, and the commits the presets produced. Before anyone acts on it, read the presets.
- Renovate docs and source were read on `main`. The cluster runs image `ghcr.io/renovatebot/renovate:44.222.0` (`the-cluster/apps/renovate/helm-release-unstoppablemango.yml`), so check version-sensitive details (for example the shell flag in §1) against that tag.
- The inventory ticket (#498) has no findings yet: no comments, and `/mnt/project-files/` held nothing else when this was written. So the failure causes in §6 come from PRs and CI logs I read myself, not from the inventory.

## TL;DR

1. **Renovate already fixes some Nix artifacts on its own, and those parts work.** In tdl the `gomod2nix` preset rewrites `nix/gomod2nix.toml` (bot commits 995a2b4, 343e0da, daae1f2) and the `nuget2nix` preset rewrites `dotnet/deps.json` (38335f8). In the-cluster, two node scripts recompute `fetchurl` and chart hashes (bot commit 3c1d681 touched `nix/crds.nix`). The nix manager updates `flake.lock` (tdl#1544, charts#143, nix#149). None of these needs nix in the Renovate pod.
2. **Most red Renovate PRs are not hash failures.** They are (a) a `flake.lock` bump that breaks the build for an unrelated reason: tree-sitter regeneration drift in tdl#1544, nixpkgs removing gtk2 in nix#149; (b) a version bumped beside a hash with no recompute step: charts#142; or (c) `main` already red, which fails every PR in pkgs.
3. **The Renovate pod cannot build Nix derivations today.** The default image installs tools through containerbase, and containerbase's `nix` tool moves the store under its cache directory (`NIX_STORE_DIR=${cache}/store`). Nothing from cache.nixos.org can be substituted into that store. That is fine for `nix flake update` and builtin fetches, but useless for `vendorHash`, `npmDepsHash`, `cargoHash` or `nix-update`, which build fixed-output derivations with go, npm or cargo inside (my inference from the source; §2).
4. **The cheapest fix is to remove the hashes, not to compute them.** Use builders that read the lock file: `importNpmLock`, `cargoLock.lockFile`, gomod2nix, `nugetDeps` JSON. tdl already does this, which is why its Renovate PRs need no hash step. Where a hash must remain (a fetched upstream `src`), compute it in a pure script the way the-cluster does, or in CI on a real Nix store.

## 1. `postUpgradeTasks` and `allowedCommands` in the-cluster's Renovate

**What Renovate does.**

- Post-upgrade tasks are "commands that are executed by Renovate after a dependency has been updated but before the commit is created". "Each command must match at least one of the patterns defined in `allowedCommands` (a global-only configuration option)" ([configuration-options.md, postUpgradeTasks](https://docs.renovatebot.com/configuration-options/#postupgradetasks)).
- Commands are Handlebars templates "compiled _prior_ to the comparison against `allowedCommands`", so the regex has to match the final string (same section).
- `fileFilters` chooses which changed files are committed. `executionMode` is `update` (once per dependency) or `branch` (once per branch). `installTools` asks containerbase for tools before the command runs, and "When using `binarySource=global`, the `installTools` options do not take effect" (same section).
- A command that fails, or matches no pattern, becomes an `artifactErrors` entry ("Post-upgrade command '…' has not been added to the allowed list in allowedCommands") rather than aborting the run ([execute-post-upgrade-commands.ts](https://github.com/renovatebot/renovate/blob/main/lib/workers/repository/update/branch/execute-post-upgrade-commands.ts), lines ~125–230). By default that error surfaces as a failing `renovate/artifacts` check ([platformAutomerge note on `statusCheckWhen.artifactError`](https://docs.renovatebot.com/configuration-options/#platformautomerge)).
- On current `main`, commands run with `shell` set by the global `allowShellExecutorForPostUpgradeCommands` (same source file). The comment in the-cluster's config still says "the command runs in a shell after templating", which may describe 44.x. Either way, anchored regexes with constrained arguments are the right defence.

**What is deployed.** There are two HelmReleases, one per GitHub App installation (`apps/renovate/helm-release-unmango.yml` and `helm-release-unstoppablemango.yml`). Each is a CronJob running every 15 minutes with `concurrencyPolicy: Forbid`, `autodiscover: true`, Redis caching, 1–2 CPU and a 4 GiB memory limit, on image `renovatebot/renovate:44.222.0`, the default image with no `-full` tag. The UnstoppableMango release allows:

| Pattern | Used by |
|---|---|
| `^node hack/renovate-fetchurl-hash\.mjs nix/… [owner/repo] v?[\d.]+$` | the-cluster: recompute a `fetchurl` hash after the regex manager bumps the URL |
| `^node hack/renovate-chart-hash\.mjs infrastructure/controllers/…/helm-release\.yml$` | the-cluster: recompute `chartHash` (a NAR hash) in `nix/crds.nix` |
| `^go run github\.com/nix-community/gomod2nix@v[\w.-]+ --dir \. --outdir [\w./-]+$` | the `gomod2nix` preset (tdl passes `nix`) |
| `^go run \./tools/nugetdeps$` | the `nuget2nix` preset (tdl only) |
| `^node overlays/update-claude-code-manifest\.mjs \d+\.\d+\.\d+$` | dotfiles |

The unmango release allows only the gomod2nix pattern. So a preset that runs anything else in an unmango/* repo fails as an artifact error.

**What running nix there would take.** Renovate's tool model: `binarySource=install` (the default) "Downloads and installs tools at runtime if running in a Containerbase environment". The `-full` image has tools preinstalled, and "If you are building your own Renovate image … you will need to ensure that all necessary tools are installed globally" ([self-hosted-configuration.md, binarySource](https://docs.renovatebot.com/self-hosted-configuration/#binarysource); [running.md](https://docs.renovatebot.com/getting-started/running/)). That leaves three options:

1. **Containerbase `nix` (works today, limited).** Containerbase knows a `nix` tool (`packageName: 'containerbase/nix-prebuild'`, [lib/util/exec/containerbase.ts](https://github.com/renovatebot/renovate/blob/main/lib/util/exec/containerbase.ts)). It is installed with these exports: `NIX_STORE_DIR=${cache}/store`, `NIX_STATE_DIR=${cache}/state`, and so on ([containerbase src/cli/tools/nix.ts](https://github.com/containerbase/base/blob/main/src/cli/tools/nix.ts)).
   - What that store can do: evaluate, `nix flake update`, `nix flake prefetch`, builtin fetchers, `nix hash`.
   - Inference: a store outside `/nix/store` gives every path a different hash, so nothing from cache.nixos.org or the Cachix caches substitutes, and building go, nodejs or cargo means bootstrapping stdenv from source in a pod with a 4 GiB limit. So a fixed-output build such as `goModules`, `npmDeps` or `cargoDeps` is out of reach.
   - Also inference: the CronJob pod is new every 15 minutes, so unless `containerbaseDir` points at a persistent volume, nix is downloaded again on every run ([containerbaseDir](https://docs.renovatebot.com/self-hosted-configuration/#containerbasedir)).
2. **A custom Renovate image with a real `/nix/store` and nix configured to substitute.** For example, built with nix2container like `pkgs/images/`, running `binarySource=global`. Then `nix-update`, or `nix build` with a fake hash, works as a post-upgrade task.
   - Costs: the pod needs disk for closures (go plus nodejs plus stdenv is several GB, my estimate), runs builds unsandboxed in a shared-kernel container, and stretches every Renovate run that takes the path.
   - It also collides with the security notes in #497: "a VM or a separate kernel, never a shared kernel plus a shared store". The store would have to be per-pod, which means pulling closures every run, the "empty store" anti-goal. This is a #499/#503 decision and should not be taken here.
3. **Leave Renovate nix-free and fix hashes in CI.** A workflow on `renovate/**` branches runs on a runner that already has a warm Nix store, recomputes hashes, and pushes a fixup commit with an App token (so checks rerun). Add that author to `gitIgnoredAuthors`, because "By default, Renovate will treat any PR as modified if another Git author has added to the branch … Renovate will not perform any further commits" ([gitIgnoredAuthors](https://docs.renovatebot.com/configuration-options/#gitignoredauthors)).
   - Inference: every rebase Renovate makes replaces the branch, so the fixup has to run again after each one. `rebaseWhen: conflicted` keeps that rare.

## 2. Renovate's nix manager (flake.lock)

- The manager reads `flake.nix`, extracts flake inputs as `git-refs` dependencies, and supports "input updates for `flake.lock`" and `lockFileMaintenance` for `flake.lock`. It is off by default (`enabled: false`) and documented as beta ([manager readme](https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/nix/readme.md), [index.ts](https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/nix/index.ts), [docs page](https://docs.renovatebot.com/modules/manager/nix/)).
- The artifact step runs `nix --extra-experimental-features 'nix-command flakes' [--extra-access-tokens github.com=…] flake update [inputs]` with `toolConstraints: [{toolName: 'nix'}]`, so containerbase installs nix on demand ([artifacts.ts](https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/nix/artifacts.ts)). That is why it works in the default image: updating a lock file needs only fetching, never building.
- It updates `flake.lock` and nothing else. A `vendorHash` or `npmDepsHash` that changes because nixpkgs changed (for example a new Go in `goModules`, which nix-update's source notes "pull in the whole derivation", nixpkgs#358844) is not touched ([nix-update dependency_hashes.py](https://github.com/Mic92/nix-update/blob/main/nix_update/dependency_hashes.py)).
- The shared preset evidently enables it with lock file maintenance. tdl#1544 shows one PR refreshing `flake.lock`, two `package-lock.json` files and `rust/Cargo.lock` together, so one break holds every lock back (tdl#1544 files list).
- `lockFileMaintenance` runs `"before 4am on monday"` by default ([lockFileMaintenance](https://docs.renovatebot.com/configuration-options/#lockfilemaintenance)). tdl's PR body says "before 4am" from its preset.

## 3. The `gomod2nix` and `nuget2nix` presets: what works and what still fails

Based on the allow-list patterns and tdl's history (I could not read the presets themselves):

- **They do work in tdl.** Bot squash commits for Go updates include `nix/gomod2nix.toml` (995a2b4 #1500, 343e0da #1496, daae1f2 #1495). The `microsoft.codeanalysis.csharp` update includes `dotnet/deps.json` (38335f8 #1174). Neither tool needs nix: gomod2nix hashes modules it downloads with go, and `tools/nugetdeps` restores with dotnet and writes what `nuget-to-json` would (tdl `AGENTS.md`, ".NET SDK").
- **Why they "still fail".** Inferred from the repos:
  1. **Scope.** The allow-list pins `--dir \.`, so only a `go.mod` at the repo root counts. pkgs has 17 `gomod2nix.toml` files and the nix repo has 4, all for *upstream* packages. No Renovate manager tracks those versions, so Renovate never bumps them and the preset never runs. pkgs and nix refresh them through `scripts/update.sh` with `nix run .#<name>.update-deps`, outside Renovate.
  2. **The nuget2nix pattern is tdl-specific** (`go run ./tools/nugetdeps`), and only the UnstoppableMango release allows it. A .NET repo in unmango/* (pkgs has a `deps.json`) cannot use it.
  3. **Neither covers the hash kinds most Nix files carry.** Across the ten repos: `npmDepsHash` appears in 20 files in pkgs and 1 in pulumipkgs; `vendorHash` in 14 in pulumipkgs and 1 in pkgs; `cargoHash` in 2 in pkgs, 1 in pulumipkgs and 1 in tdl. Plus fetched `src` hashes (charts' `upstream.nix`, the-cluster's `nix/*.nix`). These are refreshed by nix-update scripts or by hand, not by Renovate (grep over `--include=*.nix`).
  4. **Generated files besides lock files drift.** tdl#1544's `check` job failed on `make check-treesitter`: the new nixpkgs brought a tree-sitter CLI that writes a different `parser.c` (`lookahead != 0x17f` lines in the diff). No hash preset can fix that. It needs a "regenerate after flake.lock" step, the same shape as a post-upgrade task (log of job 133100654633).

## 4. nix-update, and fake-hash-then-read-the-error

- nix-update *is* the fake-hash approach. `nix_prefetch` runs `nix-build --expr 'let src = <pkg>.<attr>; in (src.overrideAttrs or …) (_: { outputHash = ""; outputHashAlgo = "sha256"; })'` and pulls the hash out of the last `got:` line of stderr with a regex. It does this for `src`, `goModules`, `npmDeps`, `cargoDeps`, `pnpmDeps`, `yarnOfflineCache`, `fetchedMavenDeps`, `mixFodDeps` and more, and handles nuget deps separately ([dependency_hashes.py](https://github.com/Mic92/nix-update/blob/main/nix_update/dependency_hashes.py)).
- So it needs a real Nix store that can build each fixed-output derivation, including its builder (go, npm, cargo). Inside Renovate that means option 2 of §1. pkgs and pulumipkgs already run it, on GitHub-hosted runners with Cachix, from `scripts/update.sh`, as `nix-update --flake <name> --override-filename <file>` (pulumipkgs adds `--version=`). Both flags are load-bearing (each repo's `AGENTS.md`).
- nix-update does not touch gomod2nix. pkgs' script runs `update-deps` afterwards ("Only gomod2nix is handled here", `pkgs/scripts/update.sh`).
- Problems with the two scripts' PRs:
  - **Superseded PRs pile up.** Branches are named per version (`update-gossamer-0.79.2`), and the script only checks for an open PR on the same branch. pkgs has gossamer #204, #205, #206 and #210 open at once, and pulumipkgs has #91, #96, #97 and #98 still open after newer bumps merged (PR lists).
  - **A red `main` blocks everything.** pkgs#210's x86_64 build failed in `mmake`'s `go-env_v1.1.0` (`git ls-remote … could not read Username`, an upstream module now unreachable). pkgs#208 failed on the hash mismatch of `gossamer-0.78.6`, which is the version on `main` (`specified: sha256-5VHJ… got: sha256-Zfb7…`). Neither failure is in the package the PR changes, and the gate is `nix build .#` of everything (logs of jobs 133463916155 and 132851059258).
- Other fake-hash tools (`nix-prefetch`, `lib.fakeHash` then reading the error by hand) work the same way and have the same requirement. What they buy over nix-update is only control over which attribute gets prefetched.
- **Without building.** A fetched source's flat or NAR hash can be computed with no nix at all: the-cluster's `renovate-fetchurl-hash.mjs` (sha256 of the asset) and `renovate-chart-hash.mjs` (expands the chart and NAR-hashes it in node, "The Renovate image has neither helm nor nix"). That is the pattern charts#142 is missing: the nix-comments preset bumped `actions-runner-controller` to 0.15.1 in `upstream.nix` but left `hash`, so CI failed with `specified: sha256-KAbZ… got: sha256-kkwW…` (job 125142573532). A git-tree `fetchFromGitHub` hash is a NAR hash of the unpacked tarball, which `nix flake prefetch github:owner/repo/<rev> --json` gives under containerbase nix with no build (inference: it is a builtin fetch). charts' generated templates also have to be regenerated after the bump (charts `AGENTS.md`), which does need a real store.

## 5. Avoiding the hash: builders that read the lock file

When the build reads the lock file Renovate already maintains, a dependency bump needs no hash step:

- **npm:** `importNpmLock` "replaces the npm dependency references in `package.json` and `package-lock.json` with paths to the Nix store" ([nixpkgs manual, importNpmLock](https://nixos.org/manual/nixpkgs/stable/#javascript-buildNpmPackage-importNpmLock)). tdl uses it (`nix/js.nix`, `nix/vscode-extension.nix`).
- **Rust:** "Using a vendored hash (`cargoHash`) is tedious … it requires that the hash is updated after every change to `Cargo.lock`. Therefore, `buildRustPackage` also supports vendoring dependencies directly from a `Cargo.lock` file using the `cargoLock` argument" ([nixpkgs manual, Importing a Cargo.lock file](https://nixos.org/manual/nixpkgs/stable/#importing-a-cargo.lock-file)). tdl uses it (`nix/rust.nix`). Git dependencies still need `outputHashes`.
- **Go:** gomod2nix: a TOML of per-module hashes computed outside Nix, refreshed by the preset. Or commit `vendor/` and use `vendorHash = null`.
- **.NET:** `nugetDeps = ./deps.json`, refreshed by the preset.

This only helps for in-repo code. Upstream packages in pkgs and pulumipkgs fetch a third party's source, so their `npmDepsHash` and `vendorHash` describe a lock file the repo does not hold. They stay on nix-update. A `cargoLock.lockFile` pointing at a vendored lock file is possible, but it means vendoring upstream lock files.

## 6. Where the observed failures come from

| PR | What changed | Why it is red or stuck | Fixable by a hash step? |
|---|---|---|---|
| tdl#1544 (open since 2026-11-09) | lock file maintenance: flake.lock, 2 package-locks, Cargo.lock | `check-treesitter` diff after nixpkgs bumped tree-sitter | No: needs a regenerate step |
| nix#149 (open since 2026-11-07) | lock file maintenance: flake.lock | nixpkgs refuses `gtk+-2.24.33` (eval error) | No: an upstream break that needs a human (pkgs#209 is the same fix by hand) |
| charts#142 | `upstream.nix` version 0.14.2 → 0.15.1 | FOD hash mismatch on the stale `hash` | Yes: a pure prefetch script, then regenerate the templates |
| charts#143 | lock file maintenance | green and `clean`, but not merged | Not a failure: charts sets no `automerge` |
| pkgs#162 (open since 2026-10-17) | lock file maintenance | `lsp4j-mcp` build failure on the new nixpkgs | No |
| pkgs#208, #210 | nix-update bumps | `main` already red (mmake, gossamer 0.78.6 hash) | No: fix `main` first |

## 7. Grouping, scheduling, rebasing and automerge

- **`rebaseWhen`.** With `auto` (the default) Renovate uses `behind-base-branch` "if configured to automerge or repository has been set to require PRs to be up to date". `conflicted` "will rebase only if the branch is conflicted". The docs advise against `conflicted` with automerge because it "could result in a broken base branch if two updates are merged one after another without testing the new versions together" ([rebaseWhen](https://docs.renovatebot.com/configuration-options/#rebasewhen)).
  - The rulesets in scm set no strict up-to-date policy (`getRequiredStatusChecks` passes only `requiredChecks`, `scm/github/components/publicRepo.ts`), so `conflicted` does not block merging.
  - What it saves: every rebase reruns CI and, if there is one, the post-upgrade hash step (inference).
- **Merge queue.** A merge queue tests each PR against the head of the base branch, which removes the risk above, and Renovate then picks `conflicted` by itself ([rebaseWhen, `auto`](https://docs.renovatebot.com/configuration-options/#rebasewhen); [automerge key concepts, GitHub Merge Queue](https://docs.renovatebot.com/key-concepts/automerge/)). But "merge queues are available in any public repository owned by an organization" ([GitHub docs reusable](https://github.com/github/docs/blob/main/data/reusables/gated-features/merge-queue.md)). The unmango org repos (charts, scm, pkgs, pulumipkgs) can have one. The UnstoppableMango user repos (tdl, nixos, the-cluster, vcs, nix, control-plane) cannot (owner types from the GitHub API).
- **Automerge on a green required check.**
  - With `platformAutomerge` (the default), Renovate enables GitHub auto-merge at PR creation, and GitHub merges once the branch rules pass. The docs require that tests be enforced through required status checks, or "the platform might merge Renovate PRs even if the repository's tests have not started" ([platformAutomerge](https://docs.renovatebot.com/configuration-options/#platformautomerge)).
  - PublicRepo sets `allowAutoMerge: true` (`publicRepo.ts` line 78), and every repo's ruleset carries `required_status_checks` (charts' rules list confirms it).
  - Renovate's own fallback automerge merges only up-to-date branches, "one branch/PR, per target branch, per run" ([automerge key concepts](https://docs.renovatebot.com/key-concepts/automerge/)). Every 15 minutes, that is at most about 4 an hour per repo (inference).
  - Of the consuming configs, only tdl and scm set `"automerge": true`; the-cluster turns it on for the `renovate` group alone.
- **Grouping and schedule.**
  - `groupName` per package family is already used heavily in the-cluster.
  - `schedule` (for example `schedule:weekly`) limits branch creation. tdl and scm use `schedule:monthly`.
  - `vulnerabilityAlerts` PRs "ignore settings like … `prConcurrentLimit`, `prHourlyLimit`, or `schedule`", so security fixes skip the line ([vulnerabilityAlerts](https://docs.renovatebot.com/configuration-options/#vulnerabilityalerts)). That matches #497's "weekly, with security fixes right away".
  - `executionMode: "branch"` runs a hash-fix task once per grouped branch instead of once per dependency ([postUpgradeTasks.executionMode](https://docs.renovatebot.com/configuration-options/#postupgradetasksexecutionmode)).
  - Splitting `flake.lock` lock file maintenance from the npm and Cargo locks keeps one break from holding all of them (inference from tdl#1544).

## Recommendation

1. **Remove hashes from in-repo builds** wherever a lock-file builder exists (§5). That covers tdl already, and any in-repo npm, Rust or Go code elsewhere. Those bumps then need only Renovate's own lock-file update and a green required check.
2. **Recompute fetched-source hashes in pure post-upgrade scripts**, on the-cluster's model (§4). Next in line: a prefetch script for charts' `upstream.nix` (plus the template regeneration, which needs a real store, so pair it with option 3 below). Move the scripts into `renovate-config` as presets and add matching `allowedCommands` to *both* HelmReleases.
3. **Recompute build-dependent hashes and regenerate generated files in CI, not in the Renovate pod.** A `renovate/**`-branch workflow on whichever runner #505 picks runs `nix-update --flake` or the repo's regenerate targets, such as `make check-treesitter`'s regeneration or `make chart-gha-runner-scale-set`, and pushes a fixup commit with the App token. That author goes in `gitIgnoredAuthors`. This keeps nix and builds out of a shared-kernel pod (#499) and reuses the warm store #497 wants.
   - Fold pkgs' and pulumipkgs' `scripts/update.sh` into the same machinery, or at least close superseded `update-<name>-*` PRs.
   - Give pkgs a per-package gate, so one broken package no longer fails every PR.
4. **Policy for #506:**
   - `rebaseWhen: conflicted`.
   - `platformAutomerge` with the required check.
   - Weekly `schedule` with `vulnerabilityAlerts` unscheduled.
   - A separate, later-scheduled `flake.lock` group.
   - Turn `automerge` on in the repos that lack it, for example charts.
   - A merge queue on the unmango org repos to cover `conflicted`'s untested-combination risk. The UnstoppableMango user repos cannot have one, so they rely on the post-merge `main` build.
5. **Accept that some bumps need a human.** A nixpkgs bump that removes a package (nix#149, pkgs#209) or breaks a build (pkgs#162) cannot be fixed by recomputing anything. The goal is that such PRs fail visibly while the rest still merge.
