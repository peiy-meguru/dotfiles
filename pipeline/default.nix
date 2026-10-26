# 管线：非 nixpkgs 项目的固定处理
#
# 两种来源，两种做法：
#
#   nyxuri          上游在 GitHub、不在 nixpkgs
#                   → 由 pipeline/materialize.sh **提前物化**到 vendor/
#                   → 构建期只读文件，flake 不依赖外部输入
#
#   windowsPointer  源码本来就在本仓库（pipeline/windows-pointer/）
#                   → 构建期从源码生成单文件 Lua 插件
#
# 结果都是「只依赖 nixpkgs」的静态产物，干净 clone 下来就能从 0 构建。
{ pkgs, lib }:
{
  nyxuri = import ./nyxuri.nix { inherit pkgs; };
  windowsPointer = import ./windows-pointer.nix { inherit pkgs lib; };
}
