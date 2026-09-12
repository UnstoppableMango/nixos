{ settings, machine, ... }:
{
  nixosModule =
    { config, ... }:
    let
      inherit (settings) account;
      files = config.clan.core.vars.generators."hercules-ci-agent-${account}".files;
    in
    {
      imports = [ (import ./vars.nix account) ];

      services.hercules-ci-agents.${account}.settings = {
        inherit (settings) concurrentTasks;
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
