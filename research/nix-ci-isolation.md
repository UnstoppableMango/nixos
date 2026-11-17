# Secure isolation for on-prem Nix CI builds

Research for UnstoppableMango/nixos#499. Researched 2026-11-17 against primary sources (upstream source code, upstream docs, vendor security advisories); every claim carries its source.
Where a claim is my inference rather than something a source states, it says so.

## The question and the bar

Which isolation boundaries can run Nix CI jobs on-prem with a persistent or warm store and still meet the bar:

| # | Rule |
|---|------|
| R1 | The boundary is a VM or separate kernel with a track record. |
| R2 | Never a shared kernel plus a shared store. |
| R3 | A job writes only its own store. |
| R4 | Anything shared is read-only and signature-checked. |
| R5 | Each rule can be checked by a `checks.*` assertion. |

Context taken from the repos:

- Hercules CI agents run on zeus, gaea and hades and build through the host's `nix-daemon`, which runs in `ci.slice` (`/home/claude/nixos/modules/ci-limits/default.nix`: "Builds run as children of nix-daemon, so its slice is where they land"). Harmonia serves that same host store, signed, to the clan (`modules/service/harmonia`).
  So today a CI build shares both the kernel and a writable store with the host, and whatever lands in that store gets signed and served to every machine. Under the bar this is the baseline that fails R1–R3.
- `ci.slice` ceilings: zeus 48 GiB, gaea 128 GiB (`machines/{zeus,gaea}/configuration.nix`), and the kubelet reserves them. Rook-ceph OSDs and rosequartz pods run on the same hosts.
- ARC runners on rosequartz: an empty ephemeral CSI volume on `/nix` per pod, a daemonless nix, and the in-cluster `ncps` substituter pinned by public key (`/home/claude/the-cluster/apps/arc-runners/helm-release.yml`).
  `ncps` checks upstream narinfos against five pinned upstream keys and re-signs them with its own key (`apps/nix-system/deployment.yml`: `--cache-upstream-public-key=…`, `--cache-sign-narinfo`).
- The `nested-containers` RuntimeClass is runc (`handler: runc-cgroup-writable`) in a user namespace (`infrastructure/configs/nested-containers/runtime-class.yml`, `docs/nested-containers.md`). It does not change the kernel boundary: every pod still shares the node kernel.

## Background: what Nix itself guarantees

The rest of this note depends on these facts.

1. **A trusted user effectively has root.** From the `trusted-users` setting docs in Nix's source: trusted users can "import unsigned realisations or unsigned input-addressed store objects", and "Adding a user to `trusted-users` is essentially equivalent to giving that user root access to the system. For example, the user can access or replace store path contents that are critical for system security." ([`src/nix/unix/daemon.cc`](https://github.com/NixOS/nix/blob/master/src/nix/unix/daemon.cc)).
2. **The daemon enforces signatures for untrusted clients.** In `AddToStoreNar` and `AddMultipleToStore` the daemon runs `if (!trusted && dontCheckSigs) dontCheckSigs = false;`. Repair is refused ("you are not privileged to repair store paths"), and the `ultimate` flag is cleared ([`src/libstore/daemon.cc`](https://github.com/NixOS/nix/blob/master/src/libstore/daemon.cc)).
   `require-sigs` defaults to `true`, and only content-addressed paths are exempt ([`globals.hh`](https://github.com/NixOS/nix/blob/master/src/libstore/include/nix/store/globals.hh)).
3. **An untrusted client cannot send an input-addressed derivation in-line.** `BuildDerivation` throws "you are not privileged to build input-addressed derivations" unless the derivation is content-addressed or the client is trusted. The source comment explains why: the output path of an in-line derivation "cannot be trusted that its outPath was calculated correctly" (`daemon.cc`).
   An untrusted client can still upload `.drv` files (they are content-addressed text) and ask for them to be built with `BuildPaths`. The daemon then computes the output path from the `.drv` itself.
4. **Which settings an untrusted client may change.** It cannot set restricted settings such as turning the sandbox off ("ignoring the client-specified setting … because it is a restricted setting and you are not a trusted user"). It can add substituters only from `trusted-substituters` (`daemon.cc`, `globals.hh`).
5. **The Nix sandbox is namespaces on the shared kernel**: private PID, mount, network, IPC and UTS namespaces, and fixed-output derivations keep the host network ([`local-settings.hh`, `sandbox`](https://github.com/NixOS/nix/blob/master/src/libstore/include/nix/store/local-settings.hh)).
   It is not a VM boundary, and it has a recent history of escapes that let a malicious derivation write the store or reach root:
   - **CVE-2024-27297**: a fixed-output derivation passes fds over abstract Unix sockets and can "modify the output of the derivation, after Nix has registered the path as 'valid' and immutable". This is direct store poisoning ([OSV](https://osv.dev/vulnerability/CVE-2024-27297)).
   - **CVE-2025-46415 / -46416 / -52991..52993** (June 2025, Nix, Lix and Guix): privilege escalations by build users, including "multiple collaborating malicious derivations that smuggle out file descriptors" ([Lix advisory](https://lix.systems/blog/2025-06-24-lix-cves/)).
   - **CVE-2026-39860** (GHSA-g3g9-5vj6-r3gj): arbitrary file overwrite as root during FOD output registration. Any user allowed to submit builds can trigger it ("allowed-users, everyone by default"), and it was introduced by the fix for CVE-2024-27297 ([NixOS Discourse advisory](https://discourse.nixos.org/t/nix-security-advisory-privilege-escalation-via-symlink-following-during-fod-output-registration/76900)).
   - **October 2026** (CVE-2026-110449..110453): an evaluator heap overflow, and "unprivileged `repair` operations could destroy and replace a legitimate store path before its contents were verified", leading to privilege escalation. Fixed in Nix 2.35.3 / 2.34.9 / 2.31.6 / 2.30.6 / 2.28.8; the 2.29, 2.32 and 2.33 lines get no fix ([NixOS Discourse](https://discourse.nixos.org/t/security-advisory-for-nix-and-lix-october-2026/80547)).

**What follows (inference from 1–5).** A derivation alone cannot squat on another derivation's input-addressed output path, because the path is a hash of the `.drv`. A fixed-output path is checked against its declared hash. So with sandboxing on and the client untrusted, poisoning needs a sandbox, daemon or kernel bug.
Four such bugs have been disclosed in the last three years. That is why a malicious derivation has to be contained by a VM boundary *around* the daemon, and why the daemon's own trust model cannot be the last line of defence.

## Option 1: microVM runners (microvm.nix with cloud-hypervisor, Firecracker or QEMU)

**Boundary.** KVM plus a userspace VMM, one guest kernel per job. microvm.nix declares NixOS guests for eight hypervisors and describes itself as "a more isolated alternative to `nixos-container`" ([README](https://github.com/microvm-nix/microvm.nix)).

- **cloud-hypervisor**: Rust, built on rust-vmm, virtio-only devices ([README](https://github.com/cloud-hypervisor/cloud-hypervisor)). No 9p, but virtiofs works through an external virtiofsd (microvm.nix hypervisor table). Three advisories:
  - GHSA-g6mw-f26h-4jgp (2023): HTTP API fd closing.
  - **GHSA-jmr4-g2hv-mjj6** (CVE-2026-27211): a guest rewrites its virtio-blk header as QCOW2 and reads host files. It needs the guest to be able to write the backing image; "Deployments using only trusted, read-only images are not affected". Fixed in v50.1/v51.0, which default to `backing_files=false`; `--landlock` mitigates.
  - **GHSA-f47p-p25q-83rh** (2026): use-after-free in virtio-block async completion.

  Sources: [cloud-hypervisor advisories](https://github.com/cloud-hypervisor/cloud-hypervisor/security/advisories).
- **Firecracker**: built for multi-tenant isolation. Production use is "only via the `jailer`" with seccomp and dropped privileges, and guest input is treated as untrusted at every trust-zone barrier ([design.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md)).
  It offers **block devices only, no 9p and no virtiofs** (microvm.nix table; "read-write or read-only disks" in the [README](https://github.com/firecracker-microvm/firecracker)). Two advisories:
  - GHSA-36j2-f825-qvgc (2026): jailer symlink host file overwrite.
  - GHSA-776c-mpj7-jm3r (2026): virtio-pci OOB write. PCI is opt-in via `--enable-pci`, the attacker needs guest root, and with a standard guest kernel the writes stay in guest memory.

  Sources: [Firecracker advisories](https://github.com/firecracker-microvm/firecracker/security/advisories).
  **Tested platforms**: Intel Cascade Lake and newer, AMD Milan and Genoa ([README "Tested platforms"](https://github.com/firecracker-microvm/firecracker#tested-platforms)). Neither zeus (Sandy Bridge-EP) nor gaea (EPYC 7502, Rome) is on the list. It would probably run on both, but outside what upstream tests (inference).
- **QEMU**: the most device emulation code, so the largest guest-reachable surface. The classic example is VENOM, CVE-2015-3456, a floppy-controller overflow ([NVD](https://nvd.nist.gov/vuln/detail/CVE-2015-3456); NVD would not render through this session's proxy, so this description is from memory). With microvm.nix's virtio-only machine model much of that surface is not configured (inference).

**KVM itself.** The kernel half has escapes too. CVE-2021-29657 was an AMD nested-SVM guest-to-host escape ([NVD](https://nvd.nist.gov/vuln/detail/CVE-2021-29657)). Disabling nested virtualisation (`kvm_amd nested=0` / `kvm_intel nested=0`) removes that class (inference from the CVE's precondition).
Even so, KVM plus a Rust VMM has a far better record than the Nix sandbox or container namespaces.

**Warm store without shared write access.** microvm.nix supports three layouts:

1. **Store disk image** (default when the host store is not shared): the guest closure goes on a read-only squashfs or **erofs** root disk (`storeOnDisk`, `storeDiskType`, which defaults to erofs) ([options.nix](https://github.com/microvm-nix/microvm.nix/blob/main/nixos-modules/microvm/options.nix)).
   A larger toolchain closure can be baked into the same kind of image and attached as a volume with `readOnly = true`. The image file is itself a host store path, so it is immutable on the host, and the hypervisor opens it read-only.
   This is the only option that works with Firecracker.
2. **Read-only virtiofs share** of a host directory mounted at `/nix/.ro-store`, with an overlay whose upper layer is a block volume (`writableStoreOverlay`), since "9p/virtiofs shares don't work currently" as an upper layer ([shares.md](https://github.com/microvm-nix/microvm.nix/blob/main/doc/src/shares.md)). Shares have a `readOnly` option.
   Caveats:
   - Sharing the host's real `/nix/store` exposes every host store path to the job. That is read-only but not minimal.
   - The guest's Nix database does not know these paths. microvm.nix registers only the VM's own closure (`registerClosure`), and the doc warns "The Nix database will forget all built packages after a reboot".
3. **Signed local substituter**: the guest starts with an empty or erofs-seeded store and substitutes from harmonia or ncps over the network with `require-sigs = true` and pinned `trusted-public-keys`. This is the only layout that meets R4's "signature-checked" by construction. The erofs and virtiofs layouts are trusted because the host built them, not because anything checks a signature.

**Enforce read-only on the host side.** virtiofsd's `--readonly` "prevent[s] write accesses from the guest" but "does not make the underlying shared directory an actual read-only mount" ([virtiofsd README](https://gitlab.com/virtio-fs/virtiofsd)).
Read-only enforced only by the guest mount flag is not read-only. RUSTSEC-2026-0147 (boxlite, CVSS 10) was exactly that: guest `CAP_SYS_ADMIN` remounted a "read-only" virtiofs share read-write. The fix was to enforce it in the VMM ([RustSec](https://rustsec.org/advisories/RUSTSEC-2026-0147)).
So use virtiofsd `--readonly` (or a read-only block device), keep virtiofsd's `--sandbox namespace` and `--seccomp kill` defaults, and make the source a read-only bind mount.

**Cost on the existing hosts.**

- Per-VM RAM is fixed (default 512 MB, shrinkable with `microvm-balloon`, per the README). Size it to the job's peak, since builds run in guest RAM.
- The `microvm@` units must go into `ci.slice`, or the kubelet reservation in `ci-limits` stops being accurate.
- Each job needs a writable volume for its overlay, wiped per job. microvm.nix does not wipe it. Per the doc, delete and recreate it.
- Zeus and gaea are bare metal with VT-x and AMD-V, so no nested virtualisation is needed.
- The ephemeral GitHub runner inside a guest exits after one job (`services.github-runners.<n>.ephemeral`, [nixpkgs options.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/continuous-integration/github-runner/options.nix)). But that module restarts the *service*, not the VM. Getting a fresh VM per job needs glue so the guest powers off and systemd recreates the VM and its volume (inference: I found no first-party "VM per job" controller in microvm.nix).
- A Hercules agent could live in a long-lived guest with its own daemon. That isolates the host, but jobs inside that one VM would still share a store.

**Checkable (R5).** Every rule is a NixOS evaluation fact, so `checks.*` can assert it:

- every share has `proto = "virtiofs"` and `readOnly = true`
- no share sources `/nix/store`, unless that is accepted
- every volume except the per-job overlay is `readOnly`
- the guest's `nix.settings.require-sigs`, `trusted-public-keys` and `sandbox`
- `boot.extraModprobeConfig` sets `nested=0`
- `microvm@` units' `Slice`

A `nixosTest` can additionally boot a guest and assert that `mount -o remount,rw` on the share fails to write through to the host. That is the RUSTSEC-2026-0147 failure mode.

**Verdict.** Meets R1–R5. cloud-hypervisor with a read-only erofs toolchain disk plus a signed substituter is the strongest fit. Firecracker is stronger hardened but block-only, and these CPUs are outside its tested matrix.

## Option 2: Kata Containers under Kubernetes

**Boundary.** Each pod sandbox is a lightweight VM (QEMU, cloud-hypervisor, Firecracker, Dragonball or StratoVirt) with its own guest kernel, plus the kata-agent inside it. The ARC runner pods would keep their shape and gain a VM boundary.

**Known escapes.** Nearly all of them are in the host-side plumbing Kata adds, not in KVM ([Kata advisories](https://github.com/kata-containers/kata-containers/security/advisories)):

- **GHSA-2gv2-cffp-j227** (CVE-2026-47243, Critical): guest root to host root through virtiofs. runtime-rs ran host virtiofsd as root with `--sandbox none --seccomp none`, and it honoured absolute-path `FUSE_SYMLINK` targets. Fixed in 3.31.0.
- **GHSA-rr59-xxvx-96qr**: the *default* `enable_annotations` lets a pod inject virtiofsd arguments (`-o source=/`), which serves the host root to the guest. Fixed in 3.31.0.
- **GHSA-mp2j-xm59-qfgw** (Critical): the `io.katacontainers.config_path` annotation loads an arbitrary config and runs a chosen binary as host root. runtime-rs ≤ 3.32.0, fixed in 4.0.0. The advisory's workaround is an admission webhook rejecting the annotation.
- GHSA-fgm4-mv68-h344: Dragonball virtio-blk guest-to-host escape.
- GHSA-5fc8-gg7w-3g5c: a host block device is hotplugged into the VM from a malformed image.
- GHSA-7fhf-v3p3-rp56: a pod annotation bind-mounts any host path into the guest.

The pattern: the pod author controls annotations, and Kata's defaults trust annotations.
Here pod authors are the owner's own manifests, which lowers the risk. But a job can create pods only if its service account allows it, and ARC runners normally get no such RBAC (inference).

**Privileged pods.** A privileged Kata container by default "attempts to expose all devices from the host". containerd needs `privileged_without_host_devices = true` on the kata runtime ([privileged.md](https://github.com/kata-containers/kata-containers/blob/main/docs/how-to/privileged.md)).
The ARC pods run dind. Under Kata, dind's privilege would be guest privilege only, which is the point. But whether Kata supports `hostUsers: false`, which the current admission policy requires for `nested-containers`, is unverified. A Kata class would need its own policy.

**Warm store.**

- The current design already fits: an empty per-pod `/nix` plus the `ncps` substituter checked against pinned keys. Kata changes only the boundary.
- Kata shares the container rootfs and volumes through virtio-fs by default (`shared_fs = "virtio-fs"`), so the per-pod `/nix` volume would be served by host virtiofsd. That is host-side code on the hot path, and it is where two of the escapes above live.
- `disable_block_device_use` controls the block-device alternative ([configuration-clh.toml.in](https://github.com/kata-containers/kata-containers/blob/main/src/runtime/config/configuration-clh.toml.in)).
- A read-only toolchain image could come from a Kubernetes image volume. Whether Kata's guest receives image volumes is unverified.

**Cost.**

- Every rosequartz node that runs runners needs KVM, a kata containerd handler and a guest image. The containerd config comes from cairn, so this is a cairn change.
- nixpkgs' `kata-runtime` is 3.32.0, Go runtime, QEMU only. It fetches upstream's prebuilt guest kernel and image tarball rather than building them ([package.nix, kata-images.nix](https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/by-name/ka/kata-runtime)). 3.32.0 includes the 3.31.0 fixes. GHSA-mp2j concerns runtime-rs, which this package does not build (inference from the advisory naming runtime-rs).
- The VM's memory comes out of pod allocatable, so it needs a RuntimeClass `overhead`.

**Checkable.** Partly. kubeconform already validates manifests (`checks.validate-flux`). A check can assert:

- the RuntimeClass handler
- that an admission policy rejects every `io.katacontainers.*` annotation
- through a cairn-side NixOS check, the rendered kata config: `enable_annotations = []`, `valid_virtio_fs_daemon_paths`, `disable_guest_seccomp`
- `privileged_without_host_devices = true`

Whether a pod actually got Kata can only be confirmed at runtime.

**Verdict.** Meets R1, R3 and R4 with the existing ncps design, and R5 with work. It adds the largest new host-side attack surface (runtime, shim, virtiofsd, annotations), and Kata has had six Critical advisories in 2026. Best choice if the GitHub ARC path has to stay in Kubernetes.

## Option 3: a NixOS VM per job (`qemu-vm.nix`)

**Boundary.** QEMU/KVM, one NixOS guest per job, built from nixpkgs' `virtualisation.*` module, the same machinery as `nixosTest`.

**Warm store.**

- By default the host's `/nix/store` is mounted at `/nix/.ro-store` with a guest overlay. Per the module, "we never want to actually write to the host Nix Store".
- On 9p the share gets `readonly=on` unless it is marked `writable`, and on virtiofs the share mode is `readonly` ([qemu-vm.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/qemu-vm.nix), lines ~343, ~1252, ~1327).
- `useNixStoreImage` builds a disk image of the closure instead.
- The `xchg` share is writable by design and has to be dropped or kept job-private.

**Cost and escapes.** The same as QEMU above. It is heavier than microvm.nix, because it is full QEMU with a larger default device model.
Its advantage is that it is the most exercised NixOS VM path: every `nixosTest` boots through it. It is essentially Option 1 with QEMU and less per-job tooling.

**Checkable.** Yes, as for Option 1: assert each `sharedDirectories.*.writable == false` and `mountHostNixStore`'s value.

**Verdict.** Meets R1–R5. Choose it over microvm.nix only if you want nixpkgs-only code.

## Option 4: Nix remote builders over SSH from an untrusted runner

**Boundary.** The network and SSH. The runner, for example an ARC pod, evaluates and hands derivations to a builder over `ssh-ng://`. The isolation of the build itself is whatever the builder provides. **The remote-builder protocol is not an isolation boundary on its own.** It moves the problem to the builder.

**Does the SSH user have to be trusted?** The manual's requirements list says the SSH user must be in `trusted-users` ([distributed-builds.md](https://github.com/NixOS/nix/blob/master/doc/manual/source/advanced-topics/distributed-builds.md)). The source is more precise ([`build-remote.cc`](https://github.com/NixOS/nix/blob/master/src/nix/build-remote/build-remote.cc)):

- If the remote reports the client is untrusted and the derivation is input-addressed, `build-remote` falls back to copying the `.drv` closure and calling `buildPathsWithResults`. That works untrusted, because `.drv`s are content-addressed and the builder recomputes output paths itself.
- Inputs are copied with `NoCheckSigs`, but for an untrusted client the daemon forces signature checking back on (`daemon.cc`). So an unsigned input-addressed path the runner built locally is **refused**.
- The workable configuration is `max-jobs = 0` on the runner, so every derivation is built or substituted on the builder, with the runner's SSH user only in `allowed-users`.
- `ssh://` (legacy) cannot report trust, so build-remote assumes trusted (the source comment says "we assume we are"). Use `ssh-ng://`.

**Can it poison the builder's store?**

- **Trusted user: yes, trivially.** It can import unsigned input-addressed objects (`trusted-users` doc, fact 1), can repair, and can turn the sandbox off. With harmonia signing the builder's store, a poisoned path is then served signed to every clan machine.
- **Untrusted user: not by protocol design.** It cannot claim output paths it did not derive (fact 3), cannot skip signatures (fact 2), and cannot change restricted settings (fact 4). But every build it submits runs in the Nix sandbox on the builder's kernel, so the escapes in fact 5 apply directly. CVE-2024-27297 is literally "modify a registered output". CVE-2026-39860 is exploitable by "all users allowed to submit builds", and the October 2026 unprivileged-`repair` bug lets an untrusted client "destroy and replace a legitimate store path".
- **Conclusion: an untrusted SSH user narrows the attack to Nix and kernel bugs, but does not meet R2 if the builder is the host.** The builder must itself be a VM (Option 1 or 3) whose store is not harmonia's, and that store is discarded or never served unsigned.

**Cost.**

- Low if layered on Option 1: one long-lived builder VM per host. A per-job builder would need an SSH key handed out per job.
- The builder's store is shared across jobs, so jobs share a writable store through the daemon. R3 holds only per daemon, not per job, unless each job gets its own builder VM.
- Outputs flow back to the runner with `NoCheckSigs` (`build-remote.cc`). The runner trusts the builder, which is the right direction.

**Checkable.** Yes on the builder:

- the CI user is in `nix.settings.allowed-users` and not in `trusted-users`
- `sandbox = true`, `require-sigs = true`
- the URI scheme in `nix.buildMachines` is `ssh-ng`
- the builder VM's store is not under a harmonia `services.harmonia` path

**Verdict.** A useful *transport*: it lets the untrusted ARC runners use a warm store on a VM. On its own it is not a boundary.

## Option 5: a separate nix daemon per job

**Boundary.** None beyond the shared kernel. Variants:

- a daemon or daemonless nix in a container with its own `/nix`: today's ARC design
- a chroot store (`--store /path`) in a user namespace
- a second daemon on a separate store directory

Every variant uses the same kernel as the host and every other job. Container and user-namespace escapes are kernel bugs; CVE-2022-0185 is a heap overflow reachable with `CAP_SYS_ADMIN` in a user namespace and was used for container escape ([NVD](https://nvd.nist.gov/vuln/detail/CVE-2022-0185); NVD would not render through this session's proxy, so this description is from memory).

**Warm store.**

- A per-job daemon has to start empty or seed from a signed substituter. That is what ARC plus ncps does today, and it *does* meet R3 and R4.
- Sharing a store directory between daemons gives a shared writable store, which is R2 and R3 broken.
- Bind-mounting host `/nix` is forbidden by the brief.

**Cost.** Lowest, and it already exists.

**Verdict.** **Fails R1.** It meets R2 only while nothing store-shaped is shared. Acceptable for code the owner wrote and runs, which is the stated population. It is not the isolation the bar asks for.

## Summary table

| Option | Boundary (R1) | Warm store without shared write | R2 | R3 | R4 | R5 | Main cost | Known escapes |
|---|---|---|---|---|---|---|---|---|
| microvm.nix + cloud-hypervisor | KVM + Rust VMM | RO erofs disk, RO virtiofs (`--readonly`), signed substituter | yes | yes | yes (substituter is signature-checked; images are host-built) | yes, eval assertions + nixosTest | glue for VM-per-job, RAM per VM in `ci.slice` | CH 2026 virtio-blk UAF, QCOW backing read (needs writable image); KVM nested-SVM |
| microvm.nix + Firecracker | KVM + jailer | RO block devices only, signed substituter | yes | yes | yes | yes | no virtiofs; hosts outside tested CPUs | jailer symlink, opt-in PCI OOB |
| Kata Containers | KVM + runtime/agent/virtiofsd | ncps (exists), per-pod volume over virtiofs | yes | yes | yes | partly | cairn containerd change, upstream prebuilt guest image | six Criticals in 2026, mostly annotations and virtiofsd |
| NixOS VM per job (qemu-vm.nix) | KVM + QEMU | RO 9p/virtiofs host store, store image | yes | yes | as Option 1 | yes | heavier than microVMs | QEMU device emulation history |
| Remote builder over SSH | none by itself | the builder's store | only if the builder is a VM | per daemon only | untrusted client: sigs enforced | yes | low | everything in fact 5 if the builder is on the host |
| Separate daemon per job | shared kernel | empty + signed substituter | yes only with nothing shared | yes | yes | yes | none | kernel and userns bugs |

## Ranked recommendation

1. **microvm.nix guests on cloud-hypervisor in `ci.slice` on zeus and gaea**, one VM per job:
   - a read-only erofs toolchain image (a host store path, attached read-only)
   - an empty tmpfs or volume overlay recreated per job
   - harmonia and ncps as `require-sigs` substituters with pinned keys
   - virtiofsd only with `--readonly` and its sandbox defaults, or no virtiofs at all
   - nested virtualisation off

   Move the Hercules agents' builds into these guests, so the host's harmonia-served store stops being written by CI. Every rule is a NixOS evaluation fact, so `checks.*` covers R5.
2. **Untrusted `ssh-ng` remote building into a builder microVM** for the ARC runners: the runner user only in `allowed-users`, runner `max-jobs = 0`, and a builder store never signed by harmonia. This gives Kubernetes jobs a warm store without changing the cluster runtime.
3. **Kata Containers (QEMU or cloud-hypervisor) for the ARC pods**, if they have to keep running inside rosequartz. It needs:
   - a cairn containerd handler
   - `privileged_without_host_devices = true`
   - `enable_annotations = []`
   - an admission policy that rejects `io.katacontainers.*` annotations
   - a runtime ≥ 3.31.0

   Keep ncps as the warm store.
4. **NixOS `qemu-vm.nix` per job**: secure, but heavier, and it buys nothing over option 1 except staying inside nixpkgs.
5. **A separate daemon per job (the status quo for ARC)**: fails R1. Keep it only for the trusted population, and never let it share a store.

Whatever is chosen, keep Nix at a fixed release: ≥ 2.35.3 / 2.34.9 / 2.31.6 / 2.30.6 / 2.28.8 for the October 2026 fixes, and never 2.29, 2.32 or 2.33. Never put a CI identity in `trusted-users`.

## Open questions (not verified here)

- Whether Kata supports `hostUsers: false` pods and Kubernetes image volumes in the guest.
- Whether a microvm.nix or third-party controller already does a fresh VM per GitHub job. None was found in microvm.nix's docs.
- Performance of virtiofs against an erofs block device for a large toolchain on Sandy Bridge-EP (zeus), which has no APICv or posted interrupts (inference from the CPU generation; not measured).
