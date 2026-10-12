{ clanLib, lib, ... }:
let
  generator = "build-host-ssh";

  # The address clan deploys to, which is how the builder reaches each client
  # when it copies the closure over.
  interface.options.address = lib.mkOption {
    type = lib.types.str;
    example = "10.0.69.11";
    description = "Address clan reaches this machine at.";
  };
in
{
  _class = "clan.service";
  manifest.name = "build-host";
  manifest.description = "Build client machines' closures on a builder machine instead of on the clients";
  manifest.categories = [ "System" ];
  manifest.readme = builtins.readFile ./README.md;

  roles.builder = {
    description = "Builds the clients' closures and copies them to the clients over SSH";
    inherit interface;

    perInstance =
      { roles, ... }:
      {
        nixosModule =
          { config, pkgs, ... }:
          {
            boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

            clan.core.vars.generators.${generator} = {
              files.id_ed25519 = { };
              files."id_ed25519.pub".secret = false;
              runtimeInputs = [ pkgs.openssh ];
              script = ''
                ssh-keygen -t ed25519 -N "" -C "root@${config.clan.core.settings.machine.name}" -f "$out"/id_ed25519
              '';
            };

            # clan runs the build and the copy to the client as root.
            programs.ssh.extraConfig = ''
              Match localuser root
                IdentityFile ${config.clan.core.vars.generators.${generator}.files.id_ed25519.path}
            '';

            # The sshd instance's host certificates name <machine>.thecluster.io,
            # but clan deploys by address, so pin each client's host key.
            programs.ssh.knownHosts = lib.mapAttrs' (
              machine: client:
              lib.nameValuePair "build-host-${machine}" {
                hostNames = [ client.settings.address ];
                publicKey = clanLib.getPublicValue {
                  flake = config.clan.core.settings.directory;
                  inherit machine;
                  generator = "openssh";
                  file = "ssh.id_ed25519.pub";
                };
              }
            ) (roles.client.machines or { });
          };
      };
  };

  roles.client = {
    description = "Deploys a closure built on the builder";
    inherit interface;

    perInstance =
      { roles, ... }:
      {
        nixosModule =
          { config, ... }:
          let
            builders = roles.builder.machines or { };
            builder = lib.head (lib.attrNames builders);
          in
          {
            assertions = [
              {
                assertion = lib.length (lib.attrNames builders) == 1;
                message = "build-host: a client needs exactly one builder.";
              }
            ];

            clan.core.networking.buildHost = "root@${builders.${builder}.settings.address}";

            users.users.root.openssh.authorizedKeys.keys = [
              (clanLib.getPublicValue {
                flake = config.clan.core.settings.directory;
                machine = builder;
                inherit generator;
                file = "id_ed25519.pub";
              })
            ];
          };
      };
  };
}
