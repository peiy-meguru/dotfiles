{ pkgs, ... }: {
  programs.niri.enable = true;

  # Windows 11 指针加速（libinput Lua 插件）。
  # 插件装到 /etc/libinput/plugins/，niri 的 cfg/input.kdl 会随之自动加上
  # mouse { accel-profile "flat"; accel-speed 0.0 }（见 home/niri.nix）。
  # 只对 04f3:026f（Elan X23 Pro 接收器）生效，其余设备原样透传。
  services.windowsPointer.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.common.default = [
      "gtk"
      "gnome"
    ];
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    FREETYPE_PROPERTIES = "autofitter:no-stem-darkening=0 cff:no-stem-darkening=0";
  };

  security.polkit.enable = true;
}
