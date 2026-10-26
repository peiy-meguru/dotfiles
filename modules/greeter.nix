# Noctalia Greeter 外观 —— 对齐 Nyxuri 出厂默认
#
# 色板与壁纸都来自管线（pipeline/nyxuri.nix）：
#   pipeline.nyxuri.palette    matugen 从 Nyxuri 壁纸提取的 M3 色板
#   pipeline.nyxuri.wallpaper  Nyxuri 自带 lawson_fuji.webp
#
# 上游锁定在 flake.nix 的 nyxuri 输入（具体 commit），
# 本文件不再保存任何从 Nyxuri 复制的文件。
{ pkgs, pipeline, ... }:
let
  palette = builtins.fromJSON (builtins.readFile pipeline.nyxuri.palette);
  wallpaper = pipeline.nyxuri.wallpaper;
in
{
  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      # 会话名用 desktop entry 的 Name=（niri 包提供 "Niri"）
      session.default = "Niri";

      appearance = {
        # Synced = 用下面这份完整调色板，而不是内置配色
        scheme = "Synced";
        theme_mode = "dark";
        # Nyxuri 的 [shell] font_family = "Noto Sans CJK SC"；
        # Noctalia Sync 会把 shell 字体同步给 greeter
        font_family = "Noto Sans CJK SC";
        corner_radius_scale = 1.0;

        # 注意：调色板必须在 [appearance.palette] 下，
        # 直接写在 [appearance] 下会被 greeter 当未知键忽略。
        #
        # greeter 用 surface_variant 画登录卡片；M3 深色下它是偏灰的
        # #444650，而 greeter 内置深色主题用的是 #1e222a。
        # 这里映射到 surface_container（#1f1f24）以贴近 Nyxuri 面板观感。
        palette = {
          inherit (palette)
            primary
            on_primary
            secondary
            on_secondary
            tertiary
            on_tertiary
            error
            on_error
            surface
            on_surface
            on_surface_variant
            outline
            shadow
            hover
            on_hover
            ;
          surface_variant = palette.surface_container;
        };

        wallpaper = {
          path = "${wallpaper}";
          fill_mode = "crop";
        };
      };

      cursor = {
        theme = "capitaine-cursors";
        size = 24;
      };
      keyboard.layout = "us";
      clock.enabled = true;
    };

    cursorTheme = {
      package = pkgs.capitaine-cursors;
      name = "capitaine-cursors";
    };
  };

  # greetd 模块只建 greeter 用户，不给 DRM 权限；
  # CachyOS 上该用户在 video 组，这里补上 video + render。
  users.users.greeter.extraGroups = [
    "video"
    "render"
  ];
}
