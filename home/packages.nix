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

    # ── 运行时（供应链安全：跟最新版，别用老版本吃已知漏洞）──────────────
    # JDK 25 是当前 nixpkgs 里最新的 JDK（jdk = jdk21 是上一个 LTS）。
    # 注意 JAVA_HOME 在 home/default.nix 里指向 ${jdk25.home}，换版本要一起改。
    jdk25
    # Node 26 是当前最新主线（nodejs = nodejs_24 是 LTS）。
    # 想跟得更紧可以换成 nodejs_latest，代价是 nixpkgs 一升级版本就静默变。
    nodejs_26
  ];
}
