{ settings, machine, ... }:
{
  nixosModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (settings) account;
      neverStart = settings.concurrentTasks == 0;
      generator = "hercules-ci-agent-${account}";
      files = config.clan.core.vars.generators.${generator}.files;
      # The upstream module names the agent's user `hci-<account>`.
      user = "hci-${account}";
    in
    {
      imports = [ (import ./vars.nix account) ];

      clan.core.vars.generators.${generator}.files =
        lib.genAttrs [ "cluster-join-token.key" "binary-caches.json" ]
          (_: {
            owner = user;
            group = user;
            restartUnits = [ "hercules-ci-agent-${account}.service" ];
          });

      # The agent refuses 0, so it gets a valid count and a unit that never runs.
      systemd.services."hercules-ci-agent-${account}".serviceConfig.ExecCondition =
        lib.mkIf neverStart "${pkgs.coreutils}/bin/false";

      services.hercules-ci-agents.${account}.settings = {
        concurrentTasks = if neverStart then 1 else settings.concurrentTasks;
        clusterJoinTokenPath = files."cluster-join-token.key".path;
        binaryCachesPath = files."binary-caches.json".path;
        labels = {
          inherit account;
          host = machine.name;
        }
        // settings.labels;
      };
    };
}
