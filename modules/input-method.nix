{ pkgs, ... }: {
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      # Wayland 原生 text-input-v3；不设 GTK_IM_MODULE / QT_IM_MODULE，
      # 避免候选窗闪烁/定位不准（与 CachyOS 上的取舍一致）
      waylandFrontend = true;
      addons = with pkgs; [
        fcitx5-rime
        fcitx5-gtk
        qt6Packages.fcitx5-qt
        fcitx5-material-color
        rime-wanxiang
      ];
    };
  };

  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULES = "wayland;fcitx";
    SDL_IM_MODULE = "fcitx";
    GLFW_IM_MODULE = "ibus";
    INPUT_METHOD = "fcitx";
  };
}
