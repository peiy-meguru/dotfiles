{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/vda";
      imageName = "nixos-vm";
      imageSize = "40G";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
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
              extraArgs = [ "-f" ];
              subvolumes = {
                "/@" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@log" = {
                  mountpoint = "/var/log";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@cache" = {
                  mountpoint = "/var/cache";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@tmp" = {
                  mountpoint = "/var/tmp";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                # snapper 要求被快照子卷内含 .snapshots
                "/@/.snapshots" = {
                  mountpoint = "/.snapshots";
                };
              };
            };
          };
        };
      };
    };
  };
}
