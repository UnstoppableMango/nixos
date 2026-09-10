# Base

Plain NixOS modules that every clan machine carries, attached through the `base` instance's `tags.all` role in `clan.nix` so a new machine inherits them without editing its `configuration.nix`.

- [dns](../../dns/default.nix): the clan-wide resolvers and the `~thecluster.lan` routing domain
- [nix](../../nix/default.nix): daemon settings that are not about where it fetches from

Substituters and trusted keys are attached separately, by the `clan-cache` instance.
