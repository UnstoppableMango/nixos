# Which system should run Nix CI?

Research for UnstoppableMango/nixos#502 (opened 2026-11-17).
Written 2026-11-17.
Every claim names the source it comes from.
"Local" means a file in the repositories under `/home/claude/`.
"Clone" means a partial `git clone` of the upstream repository taken on 2026-11-17. The GitHub REST API refused these repositories from this session, so dates come from git history.
Anything marked **unverified** could not be confirmed from a primary source here.

## The setup today

- **Hercules CI agents**, one per account (`unmango`, `unstoppablemango`), run on gaea (8 tasks), zeus (4) and hades (2) (local: `nixos/clan.nix`, instances `hercules-ci-unmango` and `hercules-ci-unstoppablemango`).
  The clan service wraps upstream's `multi-agent-service` module, which makes each agent user a Nix trusted user (local: `nixos/modules/service/hercules-ci-agent/README.md`).
  The agents hold no GC root for a task's paths, so `nh clean` stops them while it runs and `nix.gc.automatic` is asserted off (same README, hercules-ci/hercules-ci-agent#105).
  On zeus and gaea the agents share the machine with rook-ceph OSDs inside a capped `ci.slice` (local: `nixos/modules/ci-limits/default.nix`). On hades they run in a low-weight slice (local: `nixos/modules/ci-idle`).
- **Only tdl defines `herculesCI`** (local: `tdl/nix/hercules.nix`, the only `herculesCI` hit across the repositories).
  `onPush.default` builds `checks` and every package except `demo` for `ciSystems` (x86_64-linux).
  `onSchedule.nightly` runs at 04:00 UTC and builds `packages.demo` and every devShell.
  **No repository uses Hercules effects.**
- **The required check** on tdl's `main` is `required` (GitHub Actions) plus the commit status `ci/hercules/onPush/default` from the hercules-ci app, integration id 24794 (local: `vcs/github/repositories/ux.ts`, tdl#1366).
  `ci/hercules/evaluation` is left out on purpose (tdl#1344).
  An admin bypass is the way through a Hercules outage.
- **The measured outage**: the agent was unavailable from about 2026-10-26T13:28Z to 2026-10-28T02:06Z, and commits waited up to 25.4 h (tdl#1344 comment).
  Outside the outage, push → "Evaluating..." took a median 0.3 min (p90 1.4).
- **GitHub Actions**: tdl runs `nix flake check` on `ubuntu-latest` and `macos-latest`, the only darwin build anywhere, pushing to cachix (local: `tdl/.github/workflows/ci.yml`).
  pkgs uses a hosted matrix of `ubuntu-latest`, `ubuntu-24.04-arm` and `macos-latest` (local: `pkgs/.github/workflows/ci.yml`).
  nixos and pulumipkgs run on the self-hosted `thecluster` scale set (local: their `ci.yml`).
- **ARC runners** are scale sets `thecluster` (org `unmango`, 6–24 runners) and `unstoppablemango-runners` (max 6). Each pod gets its own ephemeral `/nix` and substitutes from in-cluster ncps (local: `the-cluster/apps/unmango-runners/helm-release.yml`, `the-cluster/apps/arc-runners/helm-release.yml`).
  tdl#1343 rules out a host `/nix` mount or a host daemon socket for jobs ("a node compromise").
  It also says fork PRs never run on thecluster runners.
- **Public ingress exists**: a Cloudflare tunnel already fronts `*.thecluster.io` (local: `the-cluster/apps/nextcloud/httproute.yml`, `README.md`). A webhook-driven self-hosted CI could receive GitHub webhooks through it.
- **Almost every Nix repository is public** (local: `scm/github/repos.ts`).
  `control-plane` is private (local: `vcs/github/repositories/homelab.ts`), and its CI is only `nix flake check`.

## Options compared

### 1. Hercules CI, with agents on bare metal (the status quo)

- **Evaluation and builds.** The agent evaluates the `herculesCI` attribute. Each output attribute is handled on its own, and nested sets are traversed. `ciSystems` limits a job to the listed systems. Without `onPush`, a default job builds `packages`, `checks`, `devShells`, `apps`, `nixosConfigurations`, `darwinConfigurations` and `effects` ([evaluation docs](https://docs.hercules-ci.com/hercules-ci-agent/evaluation/)).
  It never runs a whole `nix flake check`. Builds go through the machine's Nix daemon, so a path already in the store or a configured cache is not rebuilt (`binary-caches.json`, local vars generator).
- **Required checks.** Hercules posts commit statuses, not check runs, as `ci/hercules/evaluation` and `ci/hercules/<onPush|onSchedule>/<job>` (tdl#1344 measured the names). A ruleset can require them, with integration id 24794 (local: `ux.ts`).
- **Forks and secrets.** The docs reached here do not say how fork PRs are handled. tdl#1344 found the same gap, and none of tdl's 1,077 PRs came from a fork. **Unverified.**
  Effect secrets are gated by `isDefaultBranch`/`isBranch` conditions, which only hold if branch protection holds ([effects security](https://docs.hercules-ci.com/hercules-ci-agent/effects-security/)).
  If Hercules does not build a fork PR, the required `ci/hercules/onPush/default` never reports, and the PR needs the admin bypass. That is acceptable under "fork PRs go to GitHub-hosted runners" only if a hosted job also covers the flake check for forks.
- **darwin and aarch64.** Supported: "Supports Linux and macOS" ([hercules-ci.com](https://hercules-ci.com/)). Each system needs an agent or a remote builder for it.
  There is no Mac in the fleet. aarch64-linux could come from binfmt on hades or gaea (local: `machines/hades/configuration.nix`, `modules/service/build-host`).
- **Cost.** Free for open source: "unlimited agents, unlimited public source repositories, unlimited builds". The paid plan is €29/month per active user and covers private repositories ([hercules-ci.com pricing](https://hercules-ci.com/#pricing)).
  For these public repositories it costs **$0** plus electricity. One private repository would cost more than the $20 budget.
- **Homelab load.** The agents and their GC interlock already exist. The cost is the shared-node memory tuning, the hosted control plane outside your control (the 25 h outage above), and an alert that tdl#1341 says is still needed.
- **Health.** hercules-ci-agent 0.10.11 was released 2026-10-18 and 0.10.9 (Nix 2.34/2.35) on 2026-10-13. Before that, 0.10.8 came out on 2026-01-06, a nine-month gap. There are 56 commits since 2026-05-17, the last on 2026-11-11 (clone, `CHANGELOG.md`).
  hercules-ci-effects had its last commit on 2026-11-15, with 26 commits in six months, mostly flake updates (clone).
  The service is small and vendor-run, and its bus factor is not published.

### 2. GitHub Actions on self-hosted runners that hand builds to Nix remote builders

- **Evaluation and builds.** You choose: `nix flake check` (one job, one status), or per-attribute through [nix-fast-build](https://github.com/Mic92/nix-fast-build). nix-fast-build drives `nix-eval-jobs`, builds in parallel, and with `--skip-cached` builds only what is missing from the binary caches (clone: `README.md`).
  `nix-eval-jobs --check-cache-status` reports `cacheStatus` per attribute (clone: nix-eval-jobs `README.md`).
  nix-fast-build `--remote` uploads the flake and runs the whole pipeline over SSH, and `--store ssh-ng://` builds against a remote store (clone: `README.md`).
- **Required checks.** Native: job names are check runs from GitHub Actions (integration 15368, local: `scm/github/components/publicRepo.ts`). This is the same mechanism every other repository already uses.
- **Forks and secrets.** GitHub's own controls apply: the self-hosted scale sets serve only trusted events, and fork PRs go to hosted runners (tdl#1343).
  The catch is the remote builder. Handing builds to a builder's daemon needs a user the builder trusts, and Nix's `trusted-users` can import unsigned paths, which is root-equivalent on the builder (Nix manual, `trusted-users`). **Unverified wording; check the manual for your Nix version.** That is the same "node compromise" tdl#1343 refused for the host socket, moved to another host. A pod that SSHes as a trusted user to gaea is gaea's root.
- **darwin and aarch64.** Through remote builders: aarch64-linux via gaea's binfmt (already the Pis' build host, local: `modules/service/build-host/README.md`). There is no darwin builder.
- **Cost.** Self-hosted runner minutes are free. GitHub postponed the announced $0.002/min self-hosted platform charge (first set for 2026-03-01) with no new date, and "GitHub Actions will remain free for public repositories" ([changelog, 2025-12-16, updated](https://github.blog/changelog/2025-12-16-coming-soon-simpler-pricing-and-a-better-experience-for-github-actions/), [GitHub resources](https://github.com/resources/insights/2026-pricing-changes-for-github-actions)). **$0.**
- **Homelab load.** This is the highest of the options. ARC (dind, the volume fan-out bug documented in `arc-runners/helm-release.yml`), ncps, the remote builders, their SSH keys, and the trust boundary above all need upkeep.
- **Health.** ARC: gha-runner-scale-set 0.15.1 was released 2026-10-23, with 89 commits since 2026-05-17. nix-fast-build: 2.0.4 on 2026-09-28, 183 commits in six months. nix-eval-jobs: v2.35.4 on 2026-09-17, 113 commits (all from clones).

### 3. GitHub Actions on hosted runners with a binary cache

- **Evaluation and builds.** Same choice as option 2: run `nix flake check`, or nix-fast-build with `--skip-cached` against cachix, which is what its README recommends "for CI environments without a persistent Nix store, such as GitHub" (clone: nix-fast-build `README.md`).
  tdl already does this with cachix (local: `tdl/.github/workflows/ci.yml`).
- **Required checks.** Native check runs, as in option 2.
- **Forks and secrets.** A fork PR runs on a hosted runner with no repository secrets. It can still read cachix as a substituter, but it cannot push. This already satisfies "fork PRs go to GitHub-hosted runners".
- **darwin and aarch64.** Hosted `macos-latest` (aarch64-darwin) and `ubuntu-24.04-arm` are already in use (local: `pkgs/.github/workflows/ci.yml`). This is the only option with a real Mac and no hardware.
- **Cost.** Free for public repositories (GitHub resources page above). Private repositories draw on the included minutes ("over 33 hours" for Free/Pro users). cachix pricing was not checked.
- **Homelab load.** None. The costs are speed and disk: a cold runner has about 14 GB free after cleanup (tdl frees disk first), and every run re-substitutes its closure.
- **Health.** cachix-action v17 came out 2026-09-01, cachix v1.15.0 on 2026-11-16, and magic-nix-cache-action v15 on 2026-09-09 (clones).

### 4. garnix (hosted, Nix-native)

- **Evaluation and builds.** garnix builds flake attributes picked by `include`/`exclude` matchers. The default is `*.x86_64-linux.*`, `defaultPackage`/`devShell` for x86_64-linux, and every `nixosConfigurations`, `darwinConfigurations` and `homeConfigurations` ([yaml config](https://garnix.io/docs/ci/yaml_config/)).
  It builds per attribute, not through `nix flake check`. `incrementalizeBuilds` exists but is off by default. The docs pages read here do not describe skipping already-built derivations. **Unverified.**
- **Required checks.** Results appear "on GitHub (as commit and PR checks)" ([CI docs](https://garnix.io/docs/ci/)). The exact check names, and which one to require, are not on the pages read here. **Unverified.**
- **Forks and secrets.** Fork PRs are not covered in any page read here. **Unverified.**
  "Actions" run on `push` only (other triggers "will be added"), and they decrypt secrets with an age key that garnix holds ([actions docs](https://garnix.io/docs/actions/)).
  There is no schedule trigger.
- **darwin and aarch64.** The docs show `packages.aarch64-darwin.*` and aarch64-linux matchers in `include` ([yaml config](https://garnix.io/docs/ci/yaml_config/)). Capacity and minute weighting are not stated.
- **Cost.** The free tier is 1,500 CI minutes/month. Individual is $25/month for 10,000 minutes, and overage is $0.006/min ([pricing](https://garnix.io/pricing/)). For open source, "get in touch" for more ([open source](https://garnix.io/docs/open_source/)).
  The free tier probably does not cover tdl's flake (it builds smithy, ghc, dotnet AOT, and more). The first paid tier is over the $20 budget.
- **Homelab load.** None. There is no use for the bare-metal fleet unless you buy Enterprise "On-Premise Hosting".
- **Health.** The upstream repositories could not be read from this session (`garnix-io/garnix-action` does not exist under that name). An Actions blog post is dated 2025-11-25 ([garnix blog](https://garnix.io/blog/actions/)). **Unverified.**

### 5. buildbot-nix, now nixbot (self-hosted, Nix-native)

- **buildbot-nix is archived.** On 2026-10-24 its README gained "This project is archived and has been replaced by [nixbot](https://github.com/Mic92/nixbot)" (clone: nix-community/buildbot-nix commit `6e6915257`). Its last release was 1.1.0 on 2025-09-16. Do not adopt it; adopt nixbot.
- **nixbot** is a single NixOS service that handles webhooks, nix-eval-jobs evaluation, builds through the local daemon (fanning out to remote builders), and status reporting. It has its own web UI and Postgres (clone: `README.md`, `nixbot/nixbot/migrations/`).
  It has no tags or releases, with 2,106 commits since 2023-09-10 (history carried over from buildbot-nix). The last commit was 2026-11-12. nix-community runs it at nixbot.nix-community.org ([nix-community CI](https://nix-community.org/continuous-integration)).
- **Evaluation and builds.** It evaluates `.#checks` per attribute in parallel with nix-eval-jobs, plus **the flake's `herculesCI` `onPush` jobs, following hercules-ci-agent's evaluation semantics**. That includes `ciSystems`, `outputs.effects`, and the build modifiers. The last attribute is protected from GC, and the `build_reuse.py` module reuses earlier results (clone: `README.md`).
  tdl's `nix/hercules.nix` would therefore work unchanged for `onPush`.
- **Required checks.** It posts GitHub check runs. Per phase the contexts are `nixbot/nix-eval` and `nixbot/nix-build`, plus per-attribute failure contexts. The prefix is configurable through `status_context_prefix` (clone: `nixbot/nixbot/status.py`). You require `nixbot/nix-build` from your own GitHub App's id.
- **Forks and secrets.** nix-community says "Nixbot is the only CI system that supports pull requests from forked repositories" (nix-community CI page).
  An optional approval gate (`pr_approval.enable`) holds PRs whose author association is not OWNER/MEMBER/COLLABORATOR/CONTRIBUTOR behind an `action_required` check with an approve button. PRs from branches in the base repository, which covers bots, are always trusted (clone: `nixbot/nixbot/approval.py`, `config.py`).
  The default `trusted_associations` includes `CONTRIBUTOR`, so to match "only the owner and bots run on-prem", set it to `["OWNER", "MEMBER", "COLLABORATOR"]` or keep fork PRs on hosted runners.
  Effects run only on the default branch unless `effects_on_pull_requests`, which is read from the default branch's `nixbot.toml` (clone: `README.md`, `examples/nixbot.toml`).
  Builds run in the Nix sandbox, and "No arbitrary code runs outside of the Nix sandbox" (README).
- **onSchedule.** It is supported for **effects only**: the schedule loop discovers and runs `onSchedule` `effects` (clone: `nixbot/nixbot/schedules.py`, `schedule_runner.py`, migration `0002_scheduled_effects.sql`). tdl's nightly job, which builds `demo` and the devShells as plain outputs, would not run as it is written. See below.
- **darwin and aarch64.** Through Nix remote builders from the one service host (README). nix-community runs aarch64-darwin this way (nix-community CI page). Locally, aarch64-linux through gaea's binfmt; there is no darwin.
- **Cost.** $0 and self-hosted. It needs inbound webhooks, which the existing Cloudflare tunnel can carry, or `polling.py` for the default branch only (clone).
- **Homelab load.** Medium. It is one NixOS service plus Postgres on gaea, with remote builders as plain Nix `buildMachines`. That is a well-trodden clan pattern, and the builder trust stays inside the fleet, not in a pod. The agents' GC interlock goes away ("last attribute protected from GC").
  The new risks: you run the control plane yourself, it has no versioned releases, and it is a fresh rewrite (buildbot-nix → nixbot in 2026).

### 6. Others noted

- **NixCI** ([nix-ci.com](https://nix-ci.com/pricing)): free for FOSS with your own workers, or hosted workers at $0.33/h. Hosted is $36 per developer per month, over budget for private repositories. Not investigated further.
- **Hydra**: very active, with 626 commits since 2026-05-17 and the last on 2026-11-16 (clone). It is a jobset model with no native ruleset-friendly PR checks and heavy to run. Not recommended for PR gating here.

## Comparison

| | Hercules (now) | GHA self-hosted + remote builders | GHA hosted + cache | garnix | nixbot |
|---|---|---|---|---|---|
| Granularity | per attribute of `herculesCI` | your choice (nix-fast-build per attribute) | your choice | per attribute | per attribute, reads `herculesCI` |
| Skips built | via store/caches | `--skip-cached` | `--skip-cached` | unverified | yes, plus GC roots |
| Required check | commit status, app 24794 | check run, app 15368 | check run, app 15368 | GitHub checks, names unverified | check run `nixbot/nix-build`, own app |
| Fork PRs | undocumented | hosted runners | native, no secrets | undocumented | approval gate |
| darwin | needs agent (none) | none | **hosted macOS** | include matcher | needs builder (none) |
| aarch64-linux | binfmt builder | binfmt builder | hosted arm | yes | binfmt builder |
| Cost/month | $0 (public) | $0 | $0 (public) | $0 ≤1,500 min, else $25+ | $0 |
| Homelab load | medium (exists) | high | none | none | medium (new) |
| Health | active, small vendor | active | active | unverified | very active, no releases, new |

## What tdl's Hercules jobs need elsewhere

- **There are no effects to port.**
- `onPush.default` maps directly to nixbot, which reads `herculesCI` as it is.
  For garnix, it maps to an `include` of `checks.x86_64-linux.*` and `packages.x86_64-linux.*` plus an `exclude` of `packages.x86_64-linux.demo`.
  For GitHub Actions, it maps to `nix-fast-build --skip-cached --flake .#herculesCI.onPush.default.outputs` or an equivalent `--select`.
- **`onSchedule.nightly`** (demo plus devShells, 04:00 UTC):
  - GitHub Actions: a `schedule: cron: '0 4 * * *'` workflow running nix-fast-build over those attributes. It needs no ruleset change.
  - nixbot: wrap the builds in an `onSchedule` effect (a `mkEffect` whose inputs are `demo` and the devShells), since non-effect scheduled outputs are not built. Or keep the GitHub Actions cron.
  - garnix: no schedule trigger exists, so use the GitHub Actions cron.
- **Ruleset** (local: `vcs/github/repositories/ux.ts`): swap `ci/hercules/onPush/default` (app 24794) for the new context and its integration id. `herculesAppId` and the outage comments go away.
  vcs applies `main` through PKO, so add the new context in one merge and remove the old one in a later merge (local: `vcs/AGENTS.md` "Applying").

## Recommendation (ranked)

1. **Stay on Hercules for now, and add a hosted fallback.**
   It costs $0 for these public repositories, it is already built and measured, and every alternative re-buys what it does.
   Fix its real weakness, the hosted control plane and silent agent outages, with the alert tdl#1341 asked for. Keep the hosted GitHub Actions `darwin` job, the only darwin coverage that needs no hardware.
   Confirm how Hercules treats fork PRs before relying on it as a required check.
2. **Plan a move to nixbot if you want to drop the SaaS dependency.** It reads tdl's `herculesCI` unchanged, posts real check runs, and is the only Nix-native option with a fork-PR approval gate.
   It runs on the existing fleet through ordinary remote builders, so builder trust stays inside clan machines.
   Wait for a tagged release or a few months of post-rewrite stability, and run it alongside Hercules first. buildbot-nix itself is archived and should not be adopted.
3. **GitHub Actions on hosted runners with cachix and nix-fast-build `--skip-cached`** is the zero-ops option, and it is right for forks and darwin. It is too slow and disk-starved to be the main gate for tdl-sized flakes.
4. **GitHub Actions on self-hosted runners with remote builders**: avoid it. It brings back the trusted-daemon exposure tdl#1343 rejected, and it has the most moving parts.
5. **garnix**: the free tier's 1,500 minutes likely won't cover tdl, $25 is over budget, it cannot use the fleet, and several properties are unverified.
