{
  config,
  lib,
  ...
}:
let
  cfg = config.host.brave;
in
{
  options.host.brave = {
    enable = lib.mkEnableOption "Brave enterprise policy";

    managedBookmarks = lib.mkOption {
      type = with lib.types; listOf (attrsOf anything);
      default = import ./bookmarks.nix;
      description = ''
        Chromium `ManagedBookmarks` policy entries. They appear in a read-only
        folder on the bookmarks bar, named by the `toplevel_name` entry, and
        leave the rest of the user's bookmarks alone.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Brave is installed through erik's home-manager configuration, but policy
    # is read from /etc, which home-manager cannot write.
    environment.etc."brave/policies/managed/bookmarks.json".text = builtins.toJSON {
      ManagedBookmarks = cfg.managedBookmarks;
    };
  };
}
