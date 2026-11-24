# `deploy = false` keeps the private half off the clients.
instanceName: pkgs:
let
  # Bump to rotate the key: the changed validation hash makes `clan vars
  # generate` replace it and each server's private copy.
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
