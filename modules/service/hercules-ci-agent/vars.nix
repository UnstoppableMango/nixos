# Shared so each account is prompted once and every machine deploys the same
# token. Both files belong to the agent's user, which the upstream module
# names `hci-<account>`.
account:
let
  user = "hci-${account}";
  unit = "hercules-ci-agent-${account}.service";
  secret = {
    secret = true;
    owner = user;
    group = user;
    restartUnits = [ unit ];
  };
in
{
  clan.core.vars.generators."hercules-ci-agent-${account}" = {
    share = true;

    prompts.cluster-join-token = {
      description = "Cluster join token for the ${account} Hercules CI account";
      type = "hidden";
    };

    # Cache names must match the account's other agents, so paste the same
    # binary-caches.json the rosequartz agent's sealed secret carries.
    prompts.binary-caches = {
      description = "binary-caches.json for the ${account} Hercules CI account";
      type = "multiline-hidden";
    };

    files."cluster-join-token.key" = secret;
    files."binary-caches.json" = secret;

    script = ''
      cp "$prompts/cluster-join-token" "$out/cluster-join-token.key"
      cp "$prompts/binary-caches" "$out/binary-caches.json"
    '';
  };
}
