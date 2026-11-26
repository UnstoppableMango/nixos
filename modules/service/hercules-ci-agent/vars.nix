# Shared so each account is prompted once.
account: {
  clan.core.vars.generators."hercules-ci-agent-${account}" = {
    share = true;

    prompts.cluster-join-token = {
      description = "Cluster join token for the ${account} Hercules CI account";
      type = "hidden";
    };

    # Shared like the token, so every agent of an account sees the same
    # cache names.
    prompts.binary-caches = {
      description = "binary-caches.json for the ${account} Hercules CI account";
      type = "multiline-hidden";
    };

    files."cluster-join-token.key".secret = true;
    files."binary-caches.json".secret = true;

    script = ''
      cp "$prompts/cluster-join-token" "$out/cluster-join-token.key"
      cp "$prompts/binary-caches" "$out/binary-caches.json"
    '';
  };
}
