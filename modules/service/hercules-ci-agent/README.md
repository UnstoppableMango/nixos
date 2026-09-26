# Hercules CI agent

Runs a [Hercules CI](https://hercules-ci.com) agent on each machine in the `agent` role, using the upstream `hercules-ci-agent` flake's `multi-agent-service` NixOS module.

One instance is one account.
Instances for different accounts can share machines: each becomes its own `services.hercules-ci-agents.<account>` entry, running as `hci-<account>` from `/var/lib/hercules-ci-agent-<account>`.
The upstream module makes each agent user a Nix trusted user and sets `narinfo-cache-negative-ttl = 0` on the daemon.

The shared `hercules-ci-agent-<account>` vars generator prompts for two secrets, once per account:

- `cluster-join-token`: the token from the account's Hercules CI dashboard.
- `binary-caches`: the account's `binary-caches.json`.
  Cache names must match the account's other agents, so use the same file the rosequartz agents mount.

The agent holds no GC root for a task's paths once the worker that created them exits, so a collection while tasks are in flight can delete paths a later step needs (hercules-ci/hercules-ci-agent#105).
Agent machines therefore collect only while their agents are stopped.
The service makes the weekly `nh-clean` unit that `modules/gc` attaches to every machine conflict with every agent unit on the machine, so starting `nh-clean` stops the agents, and restarts them once it exits.
Tasks in flight when the agents stop are interrupted.
The timer carries a 6h `RandomizedDelaySec`, so agent machines rarely collect at the same time.
Other auto-GC (`nix.gc`, `min-free`) has no such hook and must stay off; the service asserts `nix.gc.automatic` is unset.
