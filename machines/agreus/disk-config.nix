{
  disko.devices = {
    disk.nvme1n1 = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            priority = 1;
            name = "ESP";
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ]; # Override existing partition
              subvolumes = {
                "/rootfs" = {
                  mountpoint = "/";
                };

                "/home" = {
                  mountOptions = [ "compress=zstd" ];
                  mountpoint = "/home";
                };

                # Sub(sub)volume doesn't need a mountpoint as its parent is mounted
                "/home/erik" = { };
                "/home/office" = { };

                "/nix" = {
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                  mountpoint = "/nix";
                };

                "/swap" = {
                  mountpoint = "/.swapvol";
                  swap = {
                    swapfile.size = "20M";
                  };
                };
              };

              mountpoint = "/partition-root";
              swap = {
                swapfile = {
                  size = "20M";
                };
              };
            };
          };
        };
      };
    };
  };
}
