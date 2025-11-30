{
  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      user = {
        name = "UnstoppableMango";
        email = "erik.rasmussen@unmango.dev";
      };

      push.autoSetupRemote = true;
    };
    signing = {
      format = "openpgp";
      key = "264283BBFDC491BC";
      signByDefault = true;
    };
  };
}
