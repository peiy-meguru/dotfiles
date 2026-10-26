# Nyxuri —— 物化产物（vendor/）
#
# 上游 Nyxuri 不在 nixpkgs 里。为了让本配置**只依赖 nixpkgs**，
# 它的所需部分由 pipeline/materialize.sh 提前落盘到 vendor/：
#
#   拉取上游 → 提取 configs/noctalia + nyxmellow + 壁纸
#            → 打 pipeline/patches/noctalia-idle.patch → 写 vendor/
#
# 构建期只读文件，不联网、不依赖外部 flake 输入。
# 刷新：./pipeline/materialize.sh --rev <sha>
# 校验：./pipeline/materialize.sh --check   （CI 会跑）
{ pkgs }:
{
  # 已打补丁的 Noctalia 主题引擎配置（bar / panel / dock / OSD + 模板注册）
  noctalia = ../vendor/noctalia;

  # NyxMellow：Material You 动态 fcitx5 皮肤模板
  nyxmellow = ../vendor/nyxmellow;

  # 出厂壁纸（greeter 与桌面共用）
  wallpaper = ../vendor/lawson_fuji.webp;

  # M3 色板：壁纸 → matugen 确定性生成。
  # 不物化，因为它完全是壁纸的函数，而且 matugen 在 nixpkgs 里，
  # 构建期算出来比存一份 JSON 更不容易漂移。
  # 参数对应 Nyxuri 的 [theme] wallpaper_scheme = "m3-content" / mode = "auto"（夜景→dark）
  palette =
    pkgs.runCommand "nyxuri-palette.json"
      {
        nativeBuildInputs = [
          pkgs.matugen
          pkgs.jq
        ];
      }
      ''
        matugen image ${../vendor/lawson_fuji.webp} --source-color-index 0 \
          --mode dark --type scheme-content --json hex -q \
        | jq -S -f ${./nyxuri-palette.jq} > $out
      '';
}
