{ inputs, ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs; };

    users.erik = {
      programs = {
        lutris.enable = true;
        git.signing = {
          format = "openpgp";
          key = "264283BBFDC491BC";
          signByDefault = true;
        };
      };
    };
  };
}
