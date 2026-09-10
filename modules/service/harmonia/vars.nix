# Both roles import this: servers derive the private half from it, clients read
# `pub-key.value` at eval time. `deploy = false` keeps the private half off the
# clients, which only ever need the public one.
instanceName: pkgs: {
  clan.core.vars.generators."harmonia-${instanceName}" = {
    share = true;
    files.sign-key.secret = true;
    files.sign-key.deploy = false;
    files.pub-key.secret = false;
    script = ''
      ${pkgs.nix}/bin/nix-store --generate-binary-cache-key ${instanceName}-1 \
        $out/sign-key \
        $out/pub-key
    '';
  };
}
