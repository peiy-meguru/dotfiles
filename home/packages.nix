{ pkgs, ... }: {
  home.packages = with pkgs; [
    noctalia
    kitty
    alacritty
    btop
    fastfetch
    micro
    vim
    tmux
    ripgrep
    fd
    jq
    wlsunset
    cliphist
    mpvpaper
    qt6Packages.fcitx5-configtool
    playerctl
    brightnessctl
    pavucontrol
    nautilus
    firefox
    libnotify
    xdg-utils
    # Wayland 截图（验证 bar/panel 样式用）
    grim
  ];
}
