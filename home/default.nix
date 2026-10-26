{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  # 改这里：你的用户名（同时改 modules/base.nix 与 hosts/*/default.nix）
  username = "username";
in
{
  imports = [
    ./niri.nix
    ./fish.nix
    ./kitty.nix
    ./fcitx5.nix
    ./fontconfig.nix
    ./packages.nix
    ./noctalia.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  xdg.enable = true;
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/桌面";
    documents = "${config.home.homeDirectory}/文档";
    download = "${config.home.homeDirectory}/下载";
    music = "${config.home.homeDirectory}/音乐";
    pictures = "${config.home.homeDirectory}/图片";
    videos = "${config.home.homeDirectory}/视频";
    templates = "${config.home.homeDirectory}/模板";
    publicShare = "${config.home.homeDirectory}/公共";
    extraConfig = {
      PROJECTS = "${config.home.homeDirectory}/项目";
    };
  };

  home.sessionVariables = {
    EDITOR = "micro";
    GHIDRA_INSTALL_DIR = "${config.home.homeDirectory}/opt/ghidra";
    # 指向 nixpkgs 的 JDK（包在 home/packages.nix 里），不再用手工下载的
    # ~/opt/jdk-21 —— 那样既无法审计版本，也拿不到 nixpkgs 的安全更新。
    JAVA_HOME = "${pkgs.jdk25.home}";
  };
}
