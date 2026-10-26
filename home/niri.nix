{
  config,
  lib,
  pkgs,
  hostName,
  osConfig,
  ...
}:
let
  isVm = hostName == "kotone-vm";
  niriDir = "${config.xdg.configHome}/niri";

  # 鼠标加速：由 services.windowsPointer 驱动。
  # 插件位于 libinput 之下，改写的是原始增量；这里必须把 libinput 自己的
  # 加速中和成 1.0，否则 Windows 曲线会被再乘一次。
  wp = osConfig.services.windowsPointer;

  # 鼠标加速块：插件启用时才注入（两者必须一致，否则曲线被乘两次）
  mouseBlock = lib.optionalString wp.enable (
    lib.concatStringsSep "\n" [
      "    // Windows 11 指针状态机由 libinput Lua 插件提供"
      "    // (/etc/libinput/plugins/10-windows-pointer.lua，源在"
      "    // pipeline/windows-pointer/)。插件位于 libinput **之下**，"
      "    // 所以必须把 libinput 自己的加速中和掉，否则 Windows 曲线会被再乘一次。"
      "    // flat + accel-speed 0.0 == factor 1.0 == 原样透传。"
      "    mouse {"
      "        accel-profile \"flat\""
      "        accel-speed 0.0"
      "    }"
      ""
    ]
  );

  input = pkgs.writeText "niri-input.kdl" (
    ''
      input {
          disable-power-key-handling
          focus-follows-mouse
          workspace-auto-back-and-forth
    ''
    + mouseBlock
    + ''
      }
    ''
  );

  autostart = pkgs.writeText "niri-autostart.kdl" (
    ''
      spawn-at-startup "noctalia"
      spawn-at-startup "fcitx5" "-d"
    ''
    + lib.optionalString (!isVm) ''
      spawn-at-startup "sh" "-c" "exec $HOME/.config/niri/scripts/auto-edp.sh"
      spawn-at-startup "sh" "-c" "exec $HOME/.config/niri/scripts/toggle-eyecare.sh --sync"
    ''
  );

  display = pkgs.writeText "niri-display.kdl" (
    if isVm then
      "// VM：让 niri 自动探测输出\n"
    else
      ''
        output "DP-1" {
            mode "2560x1440@200.000"
            scale 1
        }
      ''
  );
in
{
  xdg.configFile = {
    "niri/config.kdl".source = ./files/niri/config.kdl;
    "niri/__custom__.kdl".source = ./files/niri/__custom__.kdl;
    "niri/effects_normal.kdl".source = ./files/niri/effects_normal.kdl;
    "niri/effects_eyecare.kdl".source = ./files/niri/effects_eyecare.kdl;
    "niri/glow.kdl".source = ./files/niri/glow.kdl;
    "niri/cfg/animation.kdl".source = ./files/niri/cfg/animation.kdl;
    "niri/cfg/input.kdl".source = input;
    "niri/cfg/layout.kdl".source = ./files/niri/cfg/layout.kdl;
    "niri/cfg/misc.kdl".source = ./files/niri/cfg/misc.kdl;
    "niri/cfg/rules.kdl".source = ./files/niri/cfg/rules.kdl;
    "niri/cfg/autostart.kdl".source = autostart;
    "niri/cfg/display.kdl".source = display;
    "niri/scripts/auto-edp.sh" = {
      source = ./files/niri/scripts/auto-edp.sh;
      executable = true;
    };
    "niri/scripts/toggle-eyecare.sh" = {
      source = ./files/niri/scripts/toggle-eyecare.sh;
      executable = true;
    };
  };

  # effects.kdl 由 toggle-eyecare.sh 管理（可写符号链接）；
  # home-manager 只在缺失时创建，避免每次 switch 重置护眼状态。
  home.activation.niriEffects = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${niriDir}/effects.kdl" ]; then
      ln -sfn effects_normal.kdl "${niriDir}/effects.kdl"
    fi
  '';
}
