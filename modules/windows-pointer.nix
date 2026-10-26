# Windows 11 指针加速（libinput Lua 插件）
#
# 插件由 pipeline/windows-pointer.nix 从源码生成，装到
# /etc/libinput/plugins/ —— 这是 libinput 的默认搜索路径之一
# （LIBINPUT_PLUGIN_ETCDIR），niri 26.04 的
# init_libinput_plugin_system() 会 append_default_paths() 再 load_plugins()。
#
# 为什么不用 ~/.config/libinput/plugins：系统级更符合 NixOS 的声明式模型，
# 不依赖 home-manager，所有用户/会话一致。
#
# 注意：插件位于 libinput **之下**，改写的是 libinput 报告的原始增量。
# 必须同时把 libinput 自己的加速中和掉（flat + accel-speed 0.0），
# 否则 Windows 曲线会被再乘一次 —— 这一步由 home/niri.nix 依据本模块的
# enable 自动生成到 niri 的 cfg/input.kdl。
{
  config,
  lib,
  pipeline,
  ...
}:
let
  cfg = config.services.windowsPointer;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  options.services.windowsPointer = {
    enable = mkEnableOption "Windows 11 指针加速（libinput Lua 插件）";

    pointerSpeed = mkOption {
      type = types.ints.between 1 20;
      default = 10;
      description = ''
        Windows 指针速度设置，1–20。Windows 11 默认 10。
        关闭 enhancePointerPrecision 时，10 和 20 都表示恒定 1.0 倍。
      '';
    };

    enhancePointerPrecision = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Windows「提高指针精确度」（EPP）。开启时按报告幅度走 0.5×→1.6× 曲线；
        关闭时增益恒为 1.0（真 1:1 + 亚像素累加）。
      '';
    };

    displayDpi = mkOption {
      type = types.ints.between 96 480;
      default = 96;
      description = ''
        光标所在显示器的有效 DPI。96 == 100% 缩放。
        换缩放比例时改成 round(scale * 96)，例如 1.5 倍 → 144。
      '';
    };

    vendorId = mkOption {
      type = types.ints.between 0 65535;
      default = 1267; # 0x04f3
      description = "只处理这个 VID 的鼠标（默认 0x04f3 Elan Microelectronics）。";
    };

    productId = mkOption {
      type = types.ints.between 0 65535;
      default = 623; # 0x026f
      description = "只处理这个 PID 的鼠标（默认 0x026f X23 Pro 2.4G 接收器）。";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."libinput/plugins/10-windows-pointer.lua".source = pipeline.windowsPointer.build {
      inherit (cfg)
        pointerSpeed
        enhancePointerPrecision
        displayDpi
        vendorId
        productId
        ;
    };
  };
}
