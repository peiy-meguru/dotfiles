{
  config,
  hostName,
  pkgs,
  pipeline,
  ...
}:
let
  # 与 NixOS 的 i18n.inputMethod.fcitx5 内部构造保持一致，
  # 供 home 层定位合并后的 rime-data（含 rime-wanxiang）
  fcitx5Pkg = pkgs.qt6Packages.fcitx5-with-addons.override {
    addons = config.i18n.inputMethod.fcitx5.addons;
  };
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";
    extraSpecialArgs = { inherit hostName fcitx5Pkg pipeline; };
    users.username = import ../home;
  };
}
