{ ... }: {
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.flatpak.enable = true;
  services.openssh.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # NVIDIA FBSR 挂起 bug 止血（与 CachyOS 上的 10-no-suspend.conf 等价）
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  services.snapper.configs.root = {
    SUBVOLUME = "/";
    FSTYPE = "btrfs";
    TIMELINE_CREATE = false;
    NUMBER_LIMIT = 20;
    NUMBER_LIMIT_IMPORTANT = 10;
  };
}
