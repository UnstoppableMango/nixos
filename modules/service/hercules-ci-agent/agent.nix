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
      files = config.clan.core.vars.generators."hercules-ci-agent-${account}".files;
    in
    {
      imports = [ (import ./vars.nix account) ];

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
