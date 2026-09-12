{ inputs }:
{ lib, ... }:
{
  _class = "clan.service";
  manifest.name = "hercules-ci-agent";
  manifest.description = "Run a Hercules CI agent for one account on each member machine";
  manifest.categories = [ "System" ];
  manifest.readme = builtins.readFile ./README.md;

  roles.agent = {
    description = "A machine that runs this instance's account's agent";

    interface.options = {
      account = lib.mkOption {
        type = lib.types.str;
        example = "unmango";
        description = ''
          Hercules CI account the agent joins. Also names the agent in
          `services.hercules-ci-agents`, so it runs as `hci-<account>` from
          `/var/lib/hercules-ci-agent-<account>`.
        '';
      };

      concurrentTasks = lib.mkOption {
        type = lib.types.either lib.types.ints.positive (lib.types.enum [ "auto" ]);
        default = "auto";
        description = "Number of tasks the agent runs at once. `auto` uses the core count.";
      };

      labels = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Extra agent labels, merged over `account` and `host`.";
      };
    };

    perInstance = import ./agent.nix;
  };

  # The upstream module is an attrset with no key, so the module system cannot
  # dedupe it; importing it per instance would declare its options once per
  # account on the same machine.
  perMachine.nixosModule.imports = [
    inputs.hercules-ci-agent.nixosModules.multi-agent-service
  ];
}
