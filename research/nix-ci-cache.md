# Binary cache options within $20 a month

Research for UnstoppableMango/nixos#500 (part of #497, feeds #504). Researched 2026-11-17 against primary sources: vendor pricing pages and docs (fetched 2026-11-17), the attic, harmonia and ncps READMEs and docs, the Nix 2.35 reference manual, Nix's C++ source (tag `2.34.6`, the version in this session, and `master` at `29c21a7`), and the deployed config in nixos and the-cluster. Every claim cites its source.
Where a claim is my inference rather than something a source states, it says so.

Caveats on sources:

- **Cachix publishes no prices.** On 2026-11-17 `cachix.org/pricing` showed the Starter, Standard and Pro plans with "/month" and no figure, and said to contact sales. The session's proxy refused `app.cachix.org`, `*.cachix.org` and the Wayback Machine, so I could not read the existing caches' plans, sizes or settings either.
- **The project's own closure sizes are #498's to measure, and it has no findings yet.** Evaluating the flakes here failed because the session cannot fetch their GitHub inputs. §1 gives reference sizes measured against cache.nixos.org instead.
- The GitHub API refused `zhaofengli/attic`, `nix-community/harmonia` and `kalbasit/ncps` in this session, so release dates and activity come from the rendered READMEs, which showed neither.

## TL;DR

1. **No hosted cache fits the requirements at $20 a month, and none is needed for the LAN.** Cachix lists no prices (contact sales). FlakeHub Cache is paid-only and stores full copies of cache.nixos.org paths. garnix fills its cache only from its own CI, and the plan above the free tier costs $25.
2. **A warm store on gaea, served by harmonia, gives the LAN a cache with zero extra disk writes and no Ceph.** The catch is that harmonia signs everything in that store. "Read-only for PRs" holds only if nothing but `main`'s CI ever writes to it, so PR jobs need stores of their own (#499).
3. **attic is the best fit for "one writer, signed, retention controls" if a push-model cache is wanted.** Pushers never hold the signing key, tokens are scoped to push or pull per cache, and retention is per cache. Paths already on cache.nixos.org are skipped. It still calls itself "an early prototype".
4. **ncps stops earning its place once runners start warm.** Its whole write volume is re-hosting upstream NARs, and that is what broke it on Ceph. It is a LAN mirror, not a cache of anything the project builds.
5. **The six substituters in `modules/cache` can go down to three:** one own cache, nix-community and nixos-raspberrypi (that one scoped to the Pi builders), plus harmonia and the default cache.nixos.org.
6. **A blackholed substituter costs about 80 s per request at Nix's defaults** (5 attempts × 15 s connect timeout plus backoff), or about 30 s on the clan machines, whose `connect-timeout` is 5. Nix then disables it for 60 s and pays again. Without `fallback`, the build fails if the dead cache was the last one tried for a path.

## 0. What is deployed today

- **Substituters on every clan machine:** `modules/cache/default.nix` lists six: `ncps.thecluster.lan`, `mangopkgs`, `nix-community`, `nixos-raspberrypi`, `unmango` and `unstoppablemango` (the five `*.cachix.org`). cache.nixos.org is Nix's built-in default. On top of these, the harmonia client role (`modules/service/harmonia/client.nix`) adds every harmonia server but the machine itself at priority 20: apollo, gaea, hades and zeus, with hades excluded on the three CI agents (`clan.nix`, `harmonia` instance). The six #504 lists swap nixos-raspberrypi for harmonia. Both lists are covered below.
- **`connect-timeout = 5`** is set as `mkDefault` by the harmonia client role, "Without a short timeout every substituter miss stalls on it" (`client.nix`). This is a global Nix setting, so it applies to every substituter on those machines, not only to harmonia.
- **Runners** (ARC, `the-cluster/apps/arc-runners/helm-release.yml` and `apps/unmango-runners/helm-release.yml`) have daemonless Nix with only `extra-substituters = http://ncps.nix-system.svc.cluster.local:8501` beyond the default. They start with empty stores and pull through ncps.
- **ncps** (`the-cluster/apps/nix-system/deployment.yml`): `kalbasit/ncps:v0.10.1`, 3 replicas, one Ceph RGW bucket on `fast-bucket` (SSD, two replicas per the comment), Postgres (CNPG, 2 instances) for narinfo metadata, Redis for locks, `--cache-max-size=180G` with an hourly LRU pass. Its upstreams are cache.nixos.org, nix-community and the three own Cachix caches. The bucket moved off erasure-coded HDD after "slow OSDs there truncated NAR reads (UnstoppableMango/tdl#1365)" (`object-bucket-claim.yml`), and recent fixes were for truncated large NARs and slow bucket stats (the-cluster #4876, #4880, #4897).
- **Writers today:** many. cachix-action pushes to `unstoppablemango` (nixos, pkgs, pulumipkgs, charts), `mangopkgs` (pkgs) and `unmango` (pulumipkgs) through `.github/workflows/*.yml`. Hercules agents push to whatever each account's `binary-caches.json` names (`modules/service/hercules-ci-agent/vars.nix`; contents are secret). Only nixos's workflow gates the token on `push` (`authToken: ${{ github.event_name == 'push' && secrets.CACHIX_AUTH_TOKEN || '' }}`). That is one writer per repo per cache, not the single writer #497 asks for.

## 1. Closure sizes (reference points)

Measured 2026-11-17 with `nix path-info -S --store https://cache.nixos.org` against paths from `channels.nixos.org/nixos-unstable/store-paths.xz`. The figures are uncompressed NAR bytes; caches store compressed.

| Path | Closure |
| --- | --- |
| `nixos-system-nixos-26.11pre…` (the channel's minimal system) | 6.25 GB |
| `ghc-9.10.3` | 3.52 GB |
| `gnome-shell-51.0` | 2.24 GB |
| `rustc-1.99.1` | 1.79 GB |
| `go-1.26.11` | 0.28 GB |

My inference: a host closure here is several GB to 10+ GB, and a CI build closure (tdl pulls go, ghc, dotnet, node, rust, buf…) is of the same order. Almost all of it is cache.nixos.org content. What only the project builds (its packages, generated checks, the NixOS toplevels, the Pi kernel from nixos-raspberrypi) is a small fraction of that. The fraction is what decides hosted cost:

- A cache that skips upstream paths (Cachix, attic) stores only the fraction.
- A cache that copies everything (FlakeHub, ncps) stores whole closures.

ncps's 180G ceiling is the only number in the repos that bounds today's working set.

## 2. Options

### 2.1 harmonia serving a dedicated host's store

- **What it is:** serves "your /nix/store as a binary cache over http", reading the store's SQLite DB directly, with zstd, HTTP range requests for NAR streaming, and signing when `sign_key_paths` is set ([harmonia README](https://github.com/nix-community/harmonia)). It fetches nothing; the README in `modules/service/harmonia/README.md` makes the same point.
- **Cost:** $0 hosted. Disk is whatever the host's store already uses.
- **Writes per build:** zero beyond the store itself. A path enters the cache by being built or substituted into that store. To publish from a runner with its own store, the copy is `nix copy --to ssh-ng://gaea` once per new path (my inference). Reads are served from the store's disk with no second copy, which is the property #497 wants for disk wear.
- **Signing and the PR rule:** harmonia signs on the fly with the host's key, so **every path in that store is served as signed**. The module README already warns that a server "exposes every path in its store, including anything a secret ever leaked into". To keep "one writer, read-only for PRs", nothing but `main`'s CI may build in or copy into that store. PR builds must use their own store (a VM or container store, #499), and the host's `/nix` must never be mounted into a job (#497 security notes).
- **GC and retention:** none of its own. Retention is the host's Nix GC: a path survives while a GC root holds it. My inference: keep a GC root per `main` build (for example `nix build --out-link /nix/var/nix/gcroots/ci/<repo>-<n>`) and prune the oldest roots before `nix-collect-garbage`, instead of `modules/gc`'s 14-day `nh clean`, which works on profiles. There is no LRU, because Nix does not record access times.
- **HA:** a single host. Two harmonia hosts sharing a key would mean two writers. A dead server costs clients the timeout in §4.
- **Upstream composition:** none needed. Clients list it at priority 20, ahead of cache.nixos.org's 40 ([conf-file manual, `substituters`](https://nix.dev/manual/nix/latest/command-ref/conf-file.html)). Upstream paths are in the store too if the host substituted them, so the LAN gets cache.nixos.org content from it as well.
- **Off-LAN consumers** (GitHub-hosted runners for forks, darwin) cannot reach it. Something hosted must still serve them, or they build from cache.nixos.org plus source.

### 2.2 attic (self-hosted)

- **Model:** "a self-hostable Nix Binary Cache server backed by an S3-compatible storage provider". It is multi-tenant: "Individual caches (tenants) are simply restricted views of the content-addressed NAR Store and Chunk Store" ([docs.attic.rs](https://docs.attic.rs/)). Storage `type` is `"local"` or `"s3"` ([config-template.toml](https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/config-template.toml)). Postgres is recommended for production (same file).
- **Signing:** paths are signed when fetched. "The user pushing store paths does not have access to the signing key", and each cache has its own keypair ([docs](https://docs.attic.rs/print.html)). This matches one key with CI as a pusher that cannot forge signatures.
- **Permissions:** "stateless authentication using signed JWT tokens which contain permissions". Pull and push are granted per cache name pattern, with separate delete, create, configure and retention rights (`atticadm make-token`, [docs](https://docs.attic.rs/print.html)). So `main` gets a push token, and PRs get a pull token or none (a public cache).
- **Writes per build:** `attic push` or `attic watch-store` uploads each new path once, and "paths signed with this key will be skipped by default", where the key is `cache.nixos.org-1` and can be set per cache ([docs](https://docs.attic.rs/print.html)). NARs above 64 KiB are split by FastCDC into 16–256 KiB chunks (average 64 KiB) and stored zstd-compressed ([config-template.toml](https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/config-template.toml)). My inference: a rebuilt package that differs little from its last version writes only the changed chunks, so writes are lower than the NAR size. The cost is many small objects, which is exactly the access pattern ncps's README says suits low-latency storage and not slow backends (§2.3). On gaea's local NVMe that is fine; on Ceph RGW it repeats ncps's problem.
- **GC and retention:** a GC run every 12 h by default. `default-retention-period` is 0 (off) and can be set per cache, for example "6 months", by time since last access ([config-template.toml](https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/config-template.toml); `attic cache configure --retention-period`, [docs](https://docs.attic.rs/print.html)). There is no size cap. The docs call the GC LRU.
- **HA:** the server is stateless over S3 and Postgres and "can be replicated", designed for serverless platforms or a single machine ([README](https://github.com/zhaofengli/attic)). A single host on local storage has no HA.
- **Cost:** $0 on gaea's disk. If storage goes off-site for HA or for off-LAN readers: Cloudflare R2 is $0.015/GB-month with free egress, 10 GB-month free, Class A $4.50/M and Class B $0.36/M ([R2 pricing](https://developers.cloudflare.com/r2/pricing/), 2026-11-17). Backblaze B2 starts at $6.95/TB-month with egress free up to 3× storage ([B2 pricing](https://www.backblaze.com/cloud-storage/pricing), 2026-11-17), and control-plane already runs a B2 bucket. My inference: 100–200 GB of own-built chunks costs about $1.50–3 a month on R2. Chunking makes the Class A count, not the bytes, the item to watch: one million 64 KiB chunk writes is about 61 GiB, and is free.
- **Upstream composition:** the server sets priority 41 by default (cache.nixos.org is 40) ([docs](https://docs.attic.rs/print.html)). Clients list it beside cache.nixos.org and nix-community. It does not proxy them.
- **Maturity:** "Attic is still an early prototype and is looking for more testers… everything is subject to change", with a warning that the database may need resetting ([docs](https://docs.attic.rs/print.html)). It is packaged in nixpkgs with a NixOS module (`services.atticd`); I did not verify the module's options in this session.

### 2.3 ncps (pull-through proxy)

- **Model:** "ncps acts as a local binary cache for Nix, fetching store paths from upstream caches", with multi-upstream failover, signing, size-bounded LRU, HA through Redis locks, local or S3 storage, and SQLite, Postgres or MySQL ([README](https://github.com/kalbasit/ncps)). The README says CDC suits low-latency storage because it does many small chunk reads, and that "high-latency or spinning-disk storage is better served by whole-file storage with CDC off" (same).
- **Writes per build:** every NAR a client misses on is fetched upstream and written to the bucket, cache.nixos.org paths included, and on `fast-bucket` that write is replicated twice (`deployment.yml` comment on `--cache-max-size`). An empty-store runner turns its whole closure into proxy traffic. It writes nothing the project builds itself; those paths only arrive if they are already on a Cachix upstream.
- **GC and retention:** `--cache-max-size=180G` plus `--cache-lru-schedule=@every 1h` (`deployment.yml`).
- **HA:** 3 replicas, PDB `minAvailable: 1`, Postgres with 2 instances, Redis with 1 (a single point of failure, but its loss costs one lock TTL according to `redis.yml`).
- **Signing:** re-signs upstream narinfos with its own key (`--cache-sign-narinfo`). Clients then trust ncps's key for content that cache.nixos.org already signs. That is a second trust root for upstream content (my inference).
- **Is it still needed once a warm store exists?** My inference: no. On the LAN, harmonia over a warm store serves the same upstream paths from a store that already holds them, with no second copy and no Ceph. Machines with persistent stores already have their closures. The only remaining job is giving empty-store runners a fast LAN copy of upstream, and #497's destination ("No container starts with an empty store") removes that job. If an interim mirror is needed, ncps on local disk on gaea, single replica with CDC off as its README advises for slow storage, avoids Ceph without removing the extra write per NAR.

### 2.4 Cachix (paid tiers)

- **Price:** on 2026-11-17 [cachix.org/pricing](https://www.cachix.org/pricing) listed Starter 50 GiB, Standard 250 GiB and Pro 1500 GiB storage with no prices ("contact sales"). All plans have unlimited bandwidth and a Cloudflare CDN, a 14-day trial, and "a free 5 GB limit for open source projects". Storage tiers last changed in 2023, from 20/100/1000 to 50/250/1500 GB ([blog, 2023-09-12](https://blog.cachix.org/posts/2023-09-12-upgraded-storage-plans/)). Whether Starter is within $20 is unknown; ask sales.
- **GC and retention:** paths are sorted "by their last accessed date or creation date if the path was never accessed" and the oldest are deleted down to the storage limit, with warnings at 85% and 100% ([docs: garbage collection](https://docs.cachix.org/garbage-collection)). There is no time-based retention. Pins protect named paths, with `--keep-revisions` or `--keep-days` ([pins blog](https://blog.cachix.org/posts/2023-05-23-introducing-pins-permanent-nix-binary-storage/)).
- **Writes per build:** cachix-action's default daemon mode registers a post-build hook, so "Newly built store paths are pushed to the cache as they're built", and "Nix does not trigger the hook for substituted paths" ([cachix-action README](https://github.com/cachix/cachix-action)). "When pushing, paths already in the upstream NixOS cache are skipped" ([docs: garbage collection](https://docs.cachix.org/garbage-collection)). So it writes one upload per newly built path, own builds only.
- **One writer:** per-cache tokens grant "write and/or read access to only a specific binary cache" ([getting started](https://docs.cachix.org/getting-started)). One token in `main`-only CI is the single writer. The token-on-`push` pattern already in nixos's `ci.yml` is the template. The signing key lives with Cachix or the pusher; that depends on cache settings I could not read.
- **HA:** hosted, behind Cloudflare. No disk on-prem.
- **Upstream composition:** stores only what cache.nixos.org lacks, so it sits beside cache.nixos.org and nix-community rather than in front of them.
- **At project scale:** own-built paths only, so the 5 GB free tier may suffice for one consolidated public cache if retention is tight. Today there are three such caches (my inference: they look like free OSS caches, but I could not verify).

### 2.5 FlakeHub Cache

- **Price:** "$7 per device, per user, per month" as "the starting price", one plan covering Determinate Nix, Determinate Secure Packages and FlakeHub, with team plans through sales ([determinate.systems/pricing](https://determinate.systems/pricing), 2026-11-17). "FlakeHub Cache is available only on paid plans" ([docs](https://docs.determinate.systems/flakehub/cache)). The launch post priced it at "$20 per FlakeHub organization member per month", with storage and bandwidth "free during a limited introductory period, then priced at cost" ([blog, 2024-10-23](https://determinate.systems/blog/flakehub-cache-and-private-flakes)). The current pricing page states no storage price.
- **Upstream composition:** FlakeHub "maintains complete copies of all packages, including those available from cache.nixos.org" ([blog](https://determinate.systems/blog/flakehub-cache-and-private-flakes)). So it stores whole closures, which is the expensive shape for this project if storage is billed.
- **Writers:** only "trusted builders" push, with JWTs from GitHub Actions, GitLab CI/CD, Semaphore or Buildkite; there are "no ad-hoc pushes from laptops or servers". It is "not available in pull requests from forks" ([docs](https://docs.determinate.systems/flakehub/cache)). Hercules CI is not on that list. Self-hosted GitHub runners get GitHub OIDC like hosted ones, but the docs do not mention them.
- **Access:** per-flake read grants, authenticated. The docs describe no public, unauthenticated cache, so every consumer, the LAN machines included, needs a login (`determinate-nixd login`). Its examples assume Determinate Nix.
- **GC and retention:** artifacts "remain available for as long as you need them" (blog). The docs describe no controls.
- **Fit:** one seat may fit $20. Unpriced full-closure storage, mandatory auth, and coupling to Determinate's tooling do not fit.

### 2.6 garnix cache

- **Price:** Free $0 with 1,500 CI minutes a month. Individual $25 a month with 10,000 minutes, which is over budget. Extra minutes are $0.006 each. Every plan lists "Public and Private Binary Cache" ([garnix.io/pricing](https://garnix.io/pricing), 2026-11-17).
- **Model:** `https://cache.garnix.io` with key `cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=`. Private-repo derivations need a netrc token, and garnix asks clients to drop `narinfo-cache-positive-ttl` to 3600 because private paths use expiring presigned URLs ([docs: caching](https://garnix.io/docs/caching)). Its docs describe no external push. The cache holds what garnix's CI builds when its GitHub app picks up "every git push" ([docs: CI](https://garnix.io/docs/ci/)). My inference: adopting it means adopting garnix as the CI that builds, a #502/#505 decision rather than a cache choice. It also means one signing key shared with every garnix user, not the project's own.
- **GC, retention, HA:** not documented.
- **Fit:** poor. It cannot take writes from the project's own CI, its retention is unknown, and the useful plan is $25.

## 3. Comparison

| | harmonia (gaea) | attic (gaea disk, opt. R2) | ncps | Cachix | FlakeHub Cache | garnix |
| --- | --- | --- | --- | --- | --- | --- |
| Hosted cost | $0 | $0; R2 ~$1.50–3/mo for 100–200 GB | $0 | unpublished; free 5 GB OSS | from $7/user/mo + storage "at cost" | $0 or $25/mo |
| Stores upstream paths | Only if in the store | No (skips cache.nixos.org) | Yes, all | No | Yes, full copies | n/a |
| Extra writes per build | 0 | 1 per new own path, chunked | 1 per upstream miss, ×2 on Ceph | 1 upload per new own path | 1 per path incl. upstream | n/a |
| GC / retention | Host GC roots | Per-cache retention since last access | Size LRU (180G) | Size LRU + pins | Not documented | Not documented |
| One writer / signing | Host key signs whole store | Server key; push tokens | Own key re-signs upstream | Per-cache write token | Trusted-CI JWT only | garnix's key, its CI only |
| HA | Single host | Replicable over S3 + PG | 3 replicas | Hosted CDN | Hosted | Hosted |
| Reachable off-LAN | No | Only if exposed or on R2 | No | Yes | Yes (auth) | Yes |

## 4. What an unreachable substituter costs a build

From the manual ([conf-file](https://nix.dev/manual/nix/latest/command-ref/conf-file.html), Nix 2.35.6) and the source:

- `connect-timeout`: default 15 s, curl's `--connect-timeout`. `download-attempts` / `filetransfer-retry-attempts`: default 5. `stalled-download-timeout`: 300 s. `fallback`: default false; true means "Nix falls back to building from source if a binary substitute fails". `narinfo-cache-negative-ttl`: 3600 s. `narinfo-cache-positive-ttl`: 2592000 s (30 days). The `narinfo-cache-meta-ttl` for `/nix-cache-info` is 7 days ([globals.hh](https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/include/nix/store/globals.hh)).
- **Retries:** connect failures and timeouts are not on the list of curl errors treated as hopeless, so they count as transient and are retried up to `tries` times. The backoff is 250 ms × 2^(attempt−1+jitter) ([filetransfer.cc @2.34.6](https://raw.githubusercontent.com/NixOS/nix/2.34.6/src/libstore/filetransfer.cc), `RETRY_TIME_MS_DEFAULT = 250` and the switch at ~684–712).
- **Disable window:** a non-404/403 error makes the HTTP cache store print "disabling binary cache '…' for 60 seconds". Later requests in that window fail at once with "substituter … is temporarily disabled". After 60 s the cache is re-enabled and the next request pays again ([http-binary-cache-store.cc](https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/http-binary-cache-store.cc), `disable` and `checkEnabled`).
- **Opening:** if `/nix-cache-info` is not in the local disk cache, opening the store fetches it. In 2.34.6 substituters are opened one after another, and one that fails to open is dropped with a warning for the rest of the process ([store-registration.cc @2.34.6](https://raw.githubusercontent.com/NixOS/nix/2.34.6/src/libstore/store-registration.cc)). `master` opens them in parallel "so … the wait [is] the longest" rather than the sum ([store-registration.cc @master](https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/store-registration.cc)). A machine that cached the info within 7 days skips this and pays on the first narinfo query instead ([http-binary-cache-store.cc](https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/http-binary-cache-store.cc), `init`).
- **Failure:** the substitution goal tries substituters in priority order. An error from one is logged and the next one is tried. If an error is still pending when the list runs out (the last substituter tried errored), it is rethrown unless `fallback` is set, and the build fails ([substitution-goal.cc](https://raw.githubusercontent.com/NixOS/nix/master/src/libstore/build/substitution-goal.cc), ~55–95 and ~170–180). A transfer that fails mid-NAR likewise fails the parent "unless --fallback is given" (same file, ~284).

What that adds up to (my arithmetic from the above):

| Case | Cost per request until disabled |
| --- | --- |
| Blackholed host (asleep, firewall drop), default 15 s | 5 × 15 s + ~4–5 s backoff ≈ **80 s** |
| Same on clan machines (`connect-timeout = 5`) | 5 × 5 s + backoff ≈ **30 s** |
| Refused port or NXDOMAIN | a few seconds of backoff only |

- In a fresh process, add that once per dead substituter at open (sequentially in 2.34). Then repeat roughly every 60 s while the build keeps querying.
- An ephemeral runner has an empty `~/.cache/nix`, so it pays at open on every job. It also has no negative cache: every path it needs is asked of every substituter in priority order, which costs one narinfo round trip per substituter per miss. More substituters means more round trips for each path that only cache.nixos.org has.
- Persistent machines cache a miss for an hour. A path CI pushes just after a client looked for it stays invisible to that client for up to `narinfo-cache-negative-ttl`.
- The Hercules agents on apollo, gaea and zeus already "fail their startup check when any substituter is unreachable" (`clan.nix`, harmonia instance comment). That is why hades is excluded there.

## 5. Which of the six substituters could go

My inference, against #497's destination:

| Substituter | Verdict | Why |
| --- | --- | --- |
| `ncps.thecluster.lan` | **Drop** once runners start warm | Mirrors upstream only. A warm harmonia store covers the LAN; it is the cause of Ceph load and truncation bugs. |
| `unstoppablemango.cachix.org` | **Keep one own cache** | Off-LAN readers (GitHub-hosted fork and darwin jobs) need a hosted or exposed cache. Pick one and point every `main` writer at it. |
| `unmango.cachix.org` | **Merge into the one** | One writer, one key (#497 cache-writes note). Today it is written only by pulumipkgs. |
| `mangopkgs.cachix.org` | **Merge into the one** | Written only by pkgs. Its consumers would switch to the merged cache. |
| `nix-community.cachix.org` | **Keep** | Upstream for nix-community outputs. The project does not build those. |
| `nixos-raspberrypi.cachix.org` | **Keep, scoped** | The Pi kernel and firmware are prebuilt against that flake's own nixpkgs (`modules/cache` comment). Only gaea (the Pi build-host) and the Pis need it, not every machine. |
| harmonia (apollo, gaea, hades, zeus) | **Shrink to gaea** | One warm, `main`-only store is the single writer. Servers whose stores also hold PR or ad-hoc builds would serve those as signed. Hades sleeps. |

That takes every machine from 6 configured entries plus 3–4 harmonia servers down to 3 plus one harmonia server, besides cache.nixos.org, and runners from ncps to harmonia on gaea plus the one own cache.

## 6. Recommendation (ranked)

1. **harmonia on gaea's dedicated store disk, written only by `main` CI, plus one consolidated free Cachix cache for off-LAN readers.** Hosted cost is $0. It adds no write amplification and no Ceph. Retention comes from pruning GC roots. It depends on #499 giving PR jobs separate stores and on #498 confirming gaea's disk slots. Drop ncps and the two extra Cachix caches.
2. **attic on gaea's local disk instead of harmonia, optionally mirrored to R2 (~$2/mo).** Choose this if the cache must be decoupled from the CI store: a separate signing key, push-only tokens, per-cache retention, and off-LAN reach without Cachix. The costs are "early prototype" status and a second copy of own-built paths on disk.
3. **Paid Cachix,** only if sales quotes Starter (50 GiB) at $20 or less and the on-prem box falls through. It is the least work, but the price is unverified.
4. **ncps on local disk as a stopgap** while runners still start empty, then remove it.
5. **Not recommended:** FlakeHub Cache (unpriced full-closure storage, auth on every reader, Determinate tooling) and garnix (cache tied to its own CI and key, useful plan $25).
