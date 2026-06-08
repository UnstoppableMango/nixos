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
            # Or possibly
            # https://search.nixos.org/options?channel=unstable&query=terminfo
            environment.systemPackages = with pkgs; [
              # ghostty.terminfo # Eventually...
            ];
          };
      };
  };
}
