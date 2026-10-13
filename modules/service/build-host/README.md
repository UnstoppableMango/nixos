# Build host

Builds each client's closure on the builder rather than on the client, so `clan machines update <client>` does not compile on the client.
The Pis need this: without it they build their own closures, and a Pi deployed before it trusts nixos-raspberrypi.cachix.org compiles its kernel.

The builder:

- emulates aarch64-linux through binfmt;
- generates an SSH key (the `build-host-ssh` vars generator), which root uses for outgoing connections;
- pins each client's host key under the client's address, since clan deploys by address and the host certificates name `<machine>.thecluster.io`.

Each client sets `clan.core.networking.buildHost` to the builder and trusts the builder's key for root.

Deploy the builder before its clients, so it already has the substituters and binfmt they rely on.
