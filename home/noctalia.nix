# Noctalia 主题引擎配置 —— 来自管线 pipeline/nyxuri.nix
#
# 上游 Nyxuri 的 configs/noctalia/ 在构建期提取（含本地 idle 补丁），
# 本仓库不再保存副本。这里只做两件运行时才确定的事：
#   1. /home/user → 实际 $HOME
#   2. 末尾追加 [wallpaper.default]，让桌面壁纸和 greeter 一致
#
# 未纳入：tools/（orbit launcher / translate / wallpaper-picker），
# 它们是独立脚本，与 bar/panel 样式无关（管线里已剔除）。
{
  config,
  lib,
  pipeline,
  ...
}:
let
  home = config.home.homeDirectory;
  nx = pipeline.nyxuri;
in
{
  xdg.configFile = {
    # 主配置：Nyxuri 用 /home/user 占位，这里替换成真实 $HOME。
    # 末尾追加 [wallpaper.default]：Nyxuri 原配置只给了壁纸目录，
    # 具体用哪张是用户在 picker 里选的（存在 state 里）；
    # 这里钉成出厂壁纸，让桌面和 greeter 一致。
    "noctalia/noctalia-config.toml".text =
      lib.replaceStrings [ "/home/user" ] [ home ] (
        builtins.readFile "${nx.noctalia}/noctalia-config.toml"
      )
      + ''

        [wallpaper.default]
        path = "${nx.wallpaper}"
      '';

    # Noctalia 渲染模板（M3 配色注入点）
    "noctalia/templates/gtk-3.0.css".source = "${nx.noctalia}/templates/gtk-3.0.css";
    "noctalia/templates/gtk-4.0.css".source = "${nx.noctalia}/templates/gtk-4.0.css";
    "noctalia/templates/niri-glow-material-you.kdl".source =
      "${nx.noctalia}/templates/niri-glow-material-you.kdl";
    "noctalia/templates/palette.toml".source = "${nx.noctalia}/templates/palette.toml";

    # 壁纸切换 hook
    "noctalia/wallpaper-hook.sh" = {
      source = "${nx.noctalia}/wallpaper-hook.sh";
      executable = true;
    };
    "noctalia/mpvpaper-sync.sh" = {
      source = "${nx.noctalia}/mpvpaper-sync.sh";
      executable = true;
    };
    "noctalia/mpv-hook.lua".source = "${nx.noctalia}/mpv-hook.lua";
  };

  # NyxMellow fcitx5 皮肤：模板放这里，Noctalia 渲染到同目录的
  # theme.conf / panel.svg / highlight.svg
  xdg.dataFile = {
    "fcitx5/themes/nyxmellow/templates/theme.conf".source = "${nx.nyxmellow}/theme.conf";
    "fcitx5/themes/nyxmellow/templates/panel.svg".source = "${nx.nyxmellow}/panel.svg";
    "fcitx5/themes/nyxmellow/templates/highlight.svg".source = "${nx.nyxmellow}/highlight.svg";
  };

  # 跳过 Noctalia 首次运行向导（否则登录后弹「欢迎使用 Noctalia」遮住桌面）
  home.activation.noctaliaSetupDone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/state/noctalia"
    touch "$HOME/.local/state/noctalia/.setup-complete"
  '';
}
