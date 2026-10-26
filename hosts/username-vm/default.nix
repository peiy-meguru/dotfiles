{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    ./disko.nix
  ];

  networking.hostName = "username-vm";

  # VM 用最新主线内核（不引入 CachyOS 内核，避免构建时间）
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];
  boot.plymouth.enable = true;

  # VM 图形：virtio-gpu + mesa
  hardware.graphics.enable = true;

  # ── NVIDIA 驱动安装验证 ──────────────────────────────────────────
  # VM 没有 NVIDIA 硬件，所以只「安装」不「启用」：
  #   - extraModulePackages 把 open 内核模块放进 /run/current-system/kernel-modules
  #     （modinfo nvidia 可查，但不自动加载，避免 systemd-modules-load 失败）
  #   - out 提供 libnvidia-ml.so（nvidia-smi 的 RUNPATH 依赖），
  #     .bin 提供 nvidia-smi 本体
  #     注意：nvidia-x11 的 meta.outputsToInstall 只有 ["bin"]，
  #     直接写 nvidiaPackages.latest 只会装 bin，必须显式 .out
  #   - NixOS 没有 ld.so.conf、LD_LIBRARY_PATH 也不含 sw/lib，
  #     GL 走 /run/opengl-driver 的 RPATH，所以 out 里的 libGL 不会覆盖 mesa
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidiaPackages.latest.open ];
  environment.systemPackages = [
    config.boot.kernelPackages.nvidiaPackages.latest.out
    config.boot.kernelPackages.nvidiaPackages.latest.bin
  ];

  # 测试用 SSH key（无 root 自动化验证）
  users.users.username.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPuVn1sWzAfyP0VIM9wqZ4gQcjEsCF+2TVWiR1nvuJAS nixos-vm-test"
  ];

  # ── Noctalia Greeter ────────────────────────────────────────────
  # 外观（Nyxuri 色板 + 壁纸）在 modules/greeter.nix；
  # 这里只放 VM 专属：直接进 username 的密码步骤，方便 sendkey 自动化
  services.displayManager.noctalia-greeter.settings.user.default = "username";

  system.stateVersion = "26.05";
}
