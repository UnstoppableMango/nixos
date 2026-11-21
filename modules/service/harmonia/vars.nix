# Both roles import this: servers derive the private half from it, clients read
# `pub-key.value` at eval time. `deploy = false` keeps the private half off the
# clients, which only ever need the public one.
#
# To rotate the key, bump `generation`. The validation hash changes with it, so
# the next `clan vars generate` replaces the key and every server's private
# copy, which depend on it; then deploy the servers and every client.
instanceName: pkgs:
let
  # 2: rotated in #518, after hades, which held the first key, left the servers.
  generation = 2;
  keyName = "${instanceName}-${toString generation}";
in
{
  clan.core.vars.generators."harmonia-${instanceName}" = {
    share = true;
    validation = { inherit keyName; };
    files.sign-key.secret = true;
    files.sign-key.deploy = false;
    files.pub-key.secret = false;
    script = ''
      ${pkgs.nix}/bin/nix-store --generate-binary-cache-key ${keyName} \
        $out/sign-key \
        $out/pub-key
    '';
  };
}
