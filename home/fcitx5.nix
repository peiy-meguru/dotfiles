{
  config,
  lib,
  pkgs,
  fcitx5Pkg,
  ...
}:
let
  cfgDir = "${config.xdg.configHome}/fcitx5";
  rimeShared = "${fcitx5Pkg}/share/rime-data";
  # fcitx5 会回写这些文件，必须用可写副本而不是 nix store 符号链接
  writable = {
    "config" = ./files/fcitx5/config;
    "profile" = ./files/fcitx5/profile;
    "conf/classicui.conf" = ./files/fcitx5/classicui.conf;
    "conf/rime.conf" = ./files/fcitx5/rime.conf;
  };
in
{
  home.activation.fcitx5Config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${cfgDir}/conf"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (rel: src: ''
        if ! ${pkgs.coreutils}/bin/cmp -s ${src} "${cfgDir}/${rel}"; then
          ${pkgs.coreutils}/bin/install -m 600 ${src} "${cfgDir}/${rel}"
        fi
      '') writable
    )}
  '';

  # 首次（或 schema 缺失时）自动编译 Rime；之后由 fcitx5 自己维护
  home.activation.rimeDeploy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    RIME_DIR="$HOME/.local/share/fcitx5/rime"
    if [ -d "$RIME_DIR" ] && [ ! -f "$RIME_DIR/build/wanxiang.schema.yaml" ]; then
      ${pkgs.librime}/bin/rime_deployer --build "$RIME_DIR" "${rimeShared}" >/dev/null 2>&1 || true
    fi
  '';

  # Rime 用户补丁只读，符号链接即可
  xdg.dataFile = {
    "fcitx5/rime/default.custom.yaml".source = ./files/rime/default.custom.yaml;
    "fcitx5/rime/wanxiang.custom.yaml".source = ./files/rime/wanxiang.custom.yaml;
  };
}
