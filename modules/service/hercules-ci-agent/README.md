# Hercules CI agent

Runs a [Hercules CI](https://hercules-ci.com) agent on each machine in the `agent` role, using the upstream `hercules-ci-agent` flake's `multi-agent-service` NixOS module.

One instance is one account.
Instances for different accounts can share machines: each becomes its own `services.hercules-ci-agents.<account>` entry, running as `hci-<account>` from `/var/lib/hercules-ci-agent-<account>`.
The upstream module makes each agent user a Nix trusted user and sets `narinfo-cache-negative-ttl = 0` on the daemon.

The shared `hercules-ci-agent-<account>` vars generator prompts for two secrets, once per account:

- `cluster-join-token`: the token from the account's Hercules CI dashboard.
- `binary-caches`: the account's `binary-caches.json`.
  Cache names must match the account's other agents, so use the same file the rosequartz agents mount.

Nix auto-GC (`nix.gc`, `min-free`) must stay off on agent machines.
The agent holds no GC root while a task is in flight, so a collection mid-task deletes derivations the task still needs (hercules-ci/hercules-ci-agent#105).
