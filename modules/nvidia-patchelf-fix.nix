# 临时 workaround：nixpkgs#576412 / patchelf#674
#
# patchelf 0.19.2 在**单次**调用里同时设置 --interpreter 和 --set-rpath 时，
# 会生成互相重叠的 LOAD 段，使 .dynamic 落在只读页；ld.so 在 main() 之前
# 写 DT_DEBUG 就 SEGV_ACCERR。nvidia-x11 的 builder.sh 正是这么调用的：
#
#   patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
#       --set-rpath $out/lib:$libPath $bin/bin/$i
#
# 结果 nvidia-smi / nvidia-powerd / nvidia-cuda-mps-* / nvidia-debugdump
# 全部一启动就段错误（驱动本身正常，桌面和游戏不受影响）。
#
# 修法：拿 origBin/ 里的原始二进制重新打补丁，并把 rpath 与 interpreter
# 拆成两次 patchelf 调用（**先 rpath**，顺序很关键）。
#
# 等 nixpkgs 的 patchelf 升到含 NixOS/patchelf#672 的版本后可删除本模块。
{ lib, ... }:
let
  fixNvidia =
    pkg:
    pkg.overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        if [ -d "$bin/origBin" ]; then
          for i in nvidia-cuda-mps-control nvidia-cuda-mps-server nvidia-smi nvidia-debugdump nvidia-powerd; do
            [ -e "$bin/origBin/$i" ] || continue
            rpath=$(patchelf --print-rpath "$bin/bin/$i")
            interp=$(patchelf --print-interpreter "$bin/bin/$i")
            cp -f "$bin/origBin/$i" "$bin/bin/$i"
            chmod +w "$bin/bin/$i"
            patchelf --set-rpath "$rpath" "$bin/bin/$i"
            patchelf --set-interpreter "$interp" "$bin/bin/$i"
          done
        fi
      '';
    });

  fixKernelPackages =
    lp:
    lp.extend (
      self: super: {
        nvidiaPackages = super.nvidiaPackages // {
          latest = fixNvidia super.nvidiaPackages.latest;
        };
      }
    );
in
{
  nixpkgs.overlays = [
    (final: prev: {
      linuxPackages = fixKernelPackages prev.linuxPackages;
      linuxPackages_latest = fixKernelPackages prev.linuxPackages_latest;
    })
  ];
}
