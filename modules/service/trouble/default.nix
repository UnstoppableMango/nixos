{
  _class = "clan.service";
  manifest.name = "trouble";
  manifest.readme = builtins.readFile ./README.md;

  roles.server = {
    description = "A server that may need troubleshat";
    perInstance =
      { ... }:
      {
        nixosModule =
          { pkgs, ... }:
          {
            environment.systemPackages = with pkgs; [
              ghostty.terminfo
            ];
          };
      };
  };
}
