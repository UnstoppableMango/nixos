{
  disko.devices = {
    disk.nvme1n1 = {
      type = "disk";
      device = "/dev/nvme1n1";
      content = {
        type = "gpt";
        partitions = {
          games = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/game" = {
                  mountpoint = "/game";
                };
                "/game/steam" = { };
              };
            };
          };
        };
      };
    };
  };
}
