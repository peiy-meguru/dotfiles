{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
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

  home.username = "username";
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
    JAVA_HOME = "${config.home.homeDirectory}/opt/jdk-21";
  };
}
