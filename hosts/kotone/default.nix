{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking.hostName = "kotone";

  # 默认内核 6.18.57：NVIDIA 615.78.08 的 open 模块在 cache.nixos.org 有预编译
  boot.kernelPackages = pkgs.linuxPackages;
  boot.plymouth.enable = true;

  # ── 显卡 ───────────────────────────────────────────────────────────────
  # 硬件：AMD Ryzen 9 8940HX（Radeon 610M iGPU）+ NVIDIA RTX 5060 Max-Q (GB206M)
  #
  # 关键事实：card1(NVIDIA) 同时带 eDP-1 内屏和 DP-1 外接，
  #           card0(AMD 610M) 没有任何连接的输出 → dGPU 直连模式。
  # 因此**不需要 PRIME sync/offload**，也不需要 __EGL_VENDOR_LIBRARY_FILENAMES
  # 那个 chwd workaround（它匹配 class 0302，本卡是 0300，本来就不会触发）。
  hardware.graphics.enable = true;
  # 宿主机装了 lib32-nvidia-utils，32 位游戏/Steam 需要
  hardware.graphics.enable32Bit = true;
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Blackwell 只有 open kernel module；且驱动 >=560 时该选项必须显式设置
    open = true;
    # 615.78.08，与 CachyOS 上 linux-cachyos-nvidia-open 完全同版本
    branch = "latest";
    # Wayland KMS（niri 必需）
    modesetting.enable = true;
    # 休眠/挂起时保留显存（配合 logind 的挂起禁用，双保险）
    powerManagement.enable = true;
    # Max-Q 动态功耗分配（启动 nvidia-powerd）
    dynamicBoost.enable = true;
    nvidiaSettings = true;
    # VA-API 硬解（默认 true，显式写出便于阅读）
    videoAcceleration = true;
  };

  # AMD 610M 仍作为普通 DRM 设备存在，需要 amdgpu 固件
  hardware.enableRedistributableFirmware = true;

  # ── Noctalia Greeter ────────────────────────────────────────────
  # 外观（Nyxuri 色板 + 壁纸）在 modules/greeter.nix；
  # 这里只放真机专属：外接屏优先
  services.displayManager.noctalia-greeter.settings.output = {
    name = "DP-1";
    use_synced_settings = true;
  };

  # ── 文件系统 ────────────────────────────────────────────────────────
  # 与当前 CachyOS 一致的 btrfs 子卷布局。用 mkDefault，
  # 将来接入 disko / nixos-anywhere 时会自动覆盖这些定义。
  fileSystems =
    let
      rootDev = "/dev/disk/by-label/nixos";
      btrfsOpts = subvol: [
        "subvol=${subvol}"
        "compress=zstd:1"
        "noatime"
      ];
    in
    {
      "/" = lib.mkDefault {
        device = rootDev;
        fsType = "btrfs";
        options = btrfsOpts "@";
      };
      "/home" = lib.mkDefault {
        device = rootDev;
        fsType = "btrfs";
        options = btrfsOpts "@home";
      };
      "/nix" = lib.mkDefault {
        device = rootDev;
        fsType = "btrfs";
        options = btrfsOpts "@nix";
      };
      "/var/log" = lib.mkDefault {
        device = rootDev;
        fsType = "btrfs";
        options = btrfsOpts "@log";
      };
      "/var/cache" = lib.mkDefault {
        device = rootDev;
        fsType = "btrfs";
        options = btrfsOpts "@cache";
      };
      "/var/tmp" = lib.mkDefault {
        device = rootDev;
        fsType = "btrfs";
        options = btrfsOpts "@tmp";
      };
      "/boot" = lib.mkDefault {
        device = "/dev/disk/by-label/BOOT";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };
    };

  system.stateVersion = "26.05";
}
