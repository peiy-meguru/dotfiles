# nixos-config

## 架构：管线 + 固定配置

配置分两层，职责不混：

| 层 | 位置 | 管什么 |
|---|---|---|
| **管线** | `pipeline/` + `vendor/` | 上游不在 nixpkgs 的项目（Nyxuri 等）：**CI 期物化**成静态文件 |
| **固定配置** | `modules/`、`home/`、`hosts/` | nixpkgs 已有的东西（noctalia/niri/fcitx5/字体…）：直接声明 |

### 关键设计：构建期不联网

上游 Nyxuri 不在 nixpkgs 里。**没有**让 flake 直接依赖
`github:ech678/Nyxuri` —— 那样每次构建都要联网拉那个仓库，
上游一改（或被删）构建就跟着变。

改成：**CI 期物化**。`pipeline/materialize.sh` 拉上游、提取所需子集、
打本地补丁、落盘到 `vendor/`；构建期只读这些普通文件。

```text
上游 Nyxuri (commit ebfe03c…)
        │  pipeline/materialize.sh
        ▼
vendor/  noctalia/  nyxmellow/  lawson_fuji.webp  source.json
        │  pipeline/nyxuri.nix（只是路径引用）
        ▼
NixOS 配置 ← 只依赖 nixpkgs / home-manager / disko
```

结果：**干净 clone 下来就能从 0 构建**，不需要任何第三方 flake 输入。
`flake.lock` 里只有 3 个节点（nixpkgs / home-manager / disko）。

物化内容约 600 KB（壁纸占 504 KB），已入库。

### 物化命令

```bash
./pipeline/materialize.sh --rev <sha>   # 换版本（会更新 vendor/source.json）
./pipeline/materialize.sh              # 同版本重新生成
./pipeline/materialize.sh --check      # 校验 vendor/ 是否与 rev 一致（CI 跑这个）
```

`vendor/MANIFEST.md` 记录了来源和处理方式；**不要手改 `vendor/`**。

### 管线接线

```nix
# flake.nix —— 没有 nyxuri 输入
inputs = { nixpkgs; home-manager; disko; };

pipeline = import ./pipeline { inherit pkgs lib; };
specialArgs = { inherit inputs hostName pipeline; };
```

`pipeline/windows-pointer/` 是例外：源码本来就在仓库内（engine + adapter），
构建期从源码生成单文件 Lua 插件，不需要物化。

### 管线产物

| 产物 | 来源 | 生成时机 |
|---|---|---|
| `noctalia` | `vendor/noctalia/`（已打 idle 补丁） | 物化期 |
| `nyxmellow` | `vendor/nyxmellow/` | 物化期 |
| `wallpaper` | `vendor/lawson_fuji.webp` | 物化期 |
| `palette` | matugen 从壁纸算出的 M3 色板（17 键 JSON） | 构建期（确定性） |
| `windowsPointer` | `pipeline/windows-pointer/{engine,adapter}.lua` | 构建期（源码在仓库内） |

### 本地改动一律走补丁

`pipeline/patches/noctalia-idle.patch` —— 上游 idle 超时 5/6/15 分钟改成
30/31/60 分钟。**不直接改上游文件**，这样上游升级时冲突会显式暴露。

```console
$ git -C ~/Nyxuri diff configs/noctalia/noctalia-config.toml > pipeline/patches/noctalia-idle.patch
```

### 消费侧

```nix
# modules/greeter.nix
{ pipeline, ... }:
let
  palette = builtins.fromJSON (builtins.readFile pipeline.nyxuri.palette);
  wallpaper = pipeline.nyxuri.wallpaper;
in { ... }

# home/noctalia.nix
{ pipeline, ... }:
let nx = pipeline.nyxuri; in {
  xdg.configFile."noctalia/noctalia-config.toml".text =
    lib.replaceStrings [ "/home/user" ] [ home ]
      (builtins.readFile "${nx.noctalia}/noctalia-config.toml") + ...;
}
```

仓库里**不再保存任何从 Nyxuri 复制的文件**（`home/files/noctalia/`、
`modules/greeter/*.webp|json` 已删除）。

### 升级上游

```console
$ # 1. 改 flake.nix 里的 nyxuri rev
$ nix flake lock
$ # 2. 若补丁冲突，构建会失败并指出 hunk
$ nix build .#nixosConfigurations.kotone-vm.config.system.build.toplevel
$ # 3. 更新 pipeline/patches/ 后重试
```

### 加新项目

1. `flake.nix` 的 `inputs` 加 `url = "github:owner/repo/<rev>"`、`flake = false`
2. `pipeline/<project>.nix` 导出需要的产物
3. `pipeline/default.nix` 挂上
4. 消费侧用 `pipeline.<project>.<产物>`

## 鼠标：Windows 11 指针状态机（libinput Lua 插件）

libinput 默认的 `adaptive` 是速度相关曲线，增益在 **0.3×–2.0×** 之间摆动；
Windows 11 桌面指针是定点数的「逐报告状态机」，增益 0.5×→1.6× 并带亚像素累加。
手感差异就来自这里。

移植版：`github.com/junaga/windows-pointer-linux` 的引擎（BSD-3-Clause）逐位
转成 Lua 5.4，适配层换成 niri 的 libinput 插件接口。

### 为什么不需要 root

niri 26.04 在 `src/backend/tty.rs` 的 `init_libinput_plugin_system()` 里：

```rust
libinput_plugin_system_append_path(li, "$XDG_CONFIG_HOME/libinput/plugins");
libinput_plugin_system_append_default_paths(li);
libinput_plugin_system_load_plugins(li, LIBINPUT_PLUGIN_SYSTEM_FLAG_NONE);
```

所以插件就是一个普通用户文件，**不需要 daemon、LD_PRELOAD、合成器补丁**。

### 前置条件（已核对）

| 组件 | 要求 | 本机 |
|---|---|---|
| niri | 链接 `libinput_plugin_system_*@LIBINPUT_1.30` | 26.04 ✓ |
| libinput | ≥ 1.30，且编译时带 Lua | 1.31.3 + `liblua.so.5.4` ✓ |

### 关键约束：必须中和 libinput 自己的加速

插件位于 libinput **之下**，改写的是 libinput 报告的原始增量。若不关掉
libinput 的加速，Windows 曲线会被再乘一次。所以 `cfg/input.kdl` 里：

```kdl
input {
    mouse {
        accel-profile "flat"
        accel-speed 0.0      // flat + 0.0 == factor 1.0 == 原样透传
    }
}
```

### 部署：NixOS 配置项

设置全部走 `services.windowsPointer`（`modules/windows-pointer.nix`），
插件由 `pipeline/windows-pointer.nix` 从源码生成，装到
**`/etc/libinput/plugins/`**（libinput 的默认搜索路径 `LIBINPUT_PLUGIN_ETCDIR`）。

```nix
services.windowsPointer = {
  enable = true;                  # modules/desktop.nix 已开
  pointerSpeed = 10;              # 1–20，Windows 默认 10
  enhancePointerPrecision = true; # EPP；关闭则增益恒为 1.0
  displayDpi = 96;                # 96 == 100% 缩放；1.5 倍 → 144
  vendorId = 1267;                # 0x04f3 Elan Microelectronics
  productId = 623;                # 0x026f X23 Pro 2.4G 接收器
};
```

这 5 个值在构建期注入 `adapter.lua` 顶部的常量：

```lua
local POINTER_SPEED = 10
local ENHANCE_POINTER_PRECISION = true
local DISPLAY_DPI = 96
local MATCH_VID = 0x04f3
local MATCH_PID = 0x026f
```

生成方式与 dotfiles 的 `build.py` 等价（engine.lua 去掉 `return M` + adapter.lua），
但常量来自 Nix 而不是硬编码。若上游改了常量名，构建会显式失败而不是静默失效。

**niri 侧的加速中和是自动的**：`home/niri.nix` 读
`osConfig.services.windowsPointer.enable`，启用时才往生成的 `cfg/input.kdl`
里注入 `mouse { accel-profile "flat"; accel-speed 0.0 }`。两者不可能不一致。

### 验证

```console
# 1. 引擎逐位一致性（Lua 移植 vs 上游 C++ 参考实现）
$ cd ~/dotfiles/sources/windows-pointer-niri && ./conformance/run.sh
   seed 1 identical (91755 reports) ... 734055 reports matched bit for bit
   80 checks, 0 failures

# 2. VM 里 live-load（libinput 默认路径，含 /etc/libinput/plugins）
$ sudo plugin-probe
libinput info: Plugin:10-windows-pointer.lua - windows-pointer: loaded (plugin api v1) speed=10/20 epp=true dpi=96
libinput info: Plugin:10-windows-pointer.lua - windows-pointer: loaded (plugin api v1) speed=10/20 epp=true dpi=96
libinput info: Plugin:10-windows-pointer.lua - windows-pointer: attached to "X23 Pro Receiver" (vid=0x04f3 pid=0x026f)
[motion] raw=( 247.00,   0.00)

# 3. niri 侧（临时放一个用 log_error 的探针插件，绕过默认 ERROR 级别）
$ journalctl -b | grep LOAD-MARKER
LOAD-MARKER: niri loaded libinput plugins (api v1)
LOAD-MARKER: attached to X23 Pro Receiver
LOAD-MARKER: frame after windows-pointer rel=(152,0)   ← 首个报告
LOAD-MARKER: frame after windows-pointer rel=(247,0)   ← 稳态
```

VM 里 `raw` 的 152 / 247 / 248 与本地引擎对同一输入序列的输出**逐位一致**。

### 踩过的坑

- **`load_plugins` 返回 0 是成功**，失败才返回 `-ENOSYS`。
- **libinput 默认日志优先级是 ERROR**（`src/libinput.c:1878`），插件的
  `log_info` 在 niri 的 journal 里看不到；要看得用 `log_error` 或探针提级别。
- 探针必须在 `load_plugins()` **之前**提日志级别，否则加载日志被吞。
- NixOS 没有 `/bin/bash`（只有 `/bin/sh`），脚本 shebang 用 `#!/usr/bin/env bash`。
- `/dev/uinput` 是 `crw------- root root`，创建虚拟鼠标需要 root。
- **Nix 没有十六进制字面量**：`0x04f3` 会解析成 `0` + 未定义变量 `x04f3`，写十进制。
- **`git add -N` 只记录空 blob**：Nix 取 flake 源时拿到空文件，新文件必须 `git add`。
- 替换守卫不能用「替换后是否变化」判断——默认值恰好等于原值时误判，要用 `hasInfix`。
- QEMU 的 `usb-mouse` 不支持自定义 VID/PID；验证时用 uinput 造一个
  04f3:026f 的虚拟设备来复现真机那只 Elan X23 Pro 接收器。

## 结构

```text
nixos-config/
├── .github/
│   ├── workflows/ci.yml         # CI：静态检查 → 求值 → 构建
│   └── dependabot.yml           # 自动升级 CI 里按 SHA 固定的 action
├── flake.nix                    # inputs / nixosConfigurations / checks
├── vendor/                      # 物化的上游文件（勿手改，见 MANIFEST.md）
│   ├── noctalia/                # 已打补丁的 Noctalia 配置
│   ├── nyxmellow/               # fcitx5 皮肤模板
│   ├── lawson_fuji.webp         # 出厂壁纸
│   └── source.json              # 上游 repo + rev
├── pipeline/                    # 管线
│   ├── materialize.sh           # 拉上游 → 提取 → 打补丁 → 写 vendor/
│   ├── nyxuri.nix               # 只做路径引用 + 色板生成
│   ├── windows-pointer.nix      # libinput Lua 插件生成器
│   └── patches/                 # 本地改动（上游升级时冲突会显式暴露）
├── modules/                     # 系统级模块（所有 host 共用）
│   ├── base.nix                 # locale / 用户 / nix 设置
│   ├── boot.nix                 # limine + zram
│   ├── desktop.nix              # niri + portal + 字体渲染变量
│   ├── input-method.nix         # fcitx5 + rime-wanxiang
│   ├── fonts.nix                # Inter / Noto CJK / Nerd Fonts
│   ├── packages.nix             # 系统包
│   ├── services.nix             # 网络 / 蓝牙 / snapper / logind
│   ├── greeter.nix              # noctalia-greeter 外观（Nyxuri 色板）
│   ├── windows-pointer.nix      # services.windowsPointer 选项
│   └── home-manager.nix         # home-manager 接线
├── hosts/
│   ├── kotone/                  # 真机：NVIDIA dGPU 直连
│   └── kotone-vm/
│       ├── default.nix          # VM：qemu-guest / 内核 / NVIDIA 安装验证
│       └── disko.nix            # btrfs 子卷 + ESP + .snapshots
├── home/                        # 用户级（home-manager）
│   ├── default.nix              # xdg / 用户目录 / 环境变量
│   ├── niri.nix                 # niri KDL + 按 host 生成 display/autostart
│   ├── fish.nix                 # fish + starship + 别名 + 代理函数
│   ├── kitty.nix / fcitx5.nix / fontconfig.nix
│   ├── packages.nix
│   └── files/                   # 原样迁移的配置文件
└── LICENSE                      # MIT

# 以下只在本地存在，被 .gitignore 挡住、不进版本库：
#   tests/    VM 验证工具（uinput 虚拟鼠标、libinput live-load 探针）
#   scripts/  迁移脚本 / VM 启动 / 推送脚本
```

---

## 从零构建

仓库是自足的：`flake.lock` 只有 nixpkgs / home-manager / disko 三个输入，
Nyxuri 的部分已物化到 `vendor/`。

```bash
git clone <repo> && cd nixos-config

# 1. 求值（十几秒，验证选项/包/模块没问题）
nix eval --raw .#nixosConfigurations.kotone-vm.config.system.build.toplevel.drvPath

# 2. 构建 VM 镜像（约 2 分钟，不需要 root）
nix build .#nixosConfigurations.kotone-vm.config.system.build.diskoImagesScript
./result --build-memory 4096        # 产出 nixos-vm.raw

# 3. 启动看效果（需要 qemu + edk2-ovmf）
qemu-system-x86_64 -enable-kvm -cpu host -smp 8 -m 8192 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=/usr/share/edk2/x64/OVMF_VARS.4m.fd \
  -drive file=nixos-vm.raw,if=virtio,format=raw,snapshot=on \
  -device virtio-vga-gl -display gtk,gl=on
```

VM 内登录：`username` / `nixos`（`initialPassword`，仅 VM）。

装到真机：`nixos-anywhere --flake .#username root@<目标机>`，
或按 `hosts/username/disko.nix` 自己分区后 `nixos-install --flake .#username`。

### 驱动分支选择

| nixpkgs 分支 | 版本 | 结论 |
|---|---|---|
| `latest` / `bleeding_edge` / `new_feature` | **615.78.08** | ✅ 采用 |
| `stable` / `production` | 595.104.02 | 落后一个分支 |
| `beta` | 595.45.04 | — |
| `legacy_580` | 580.178.04 | 老卡 |

`nvidia-open-615.78.08-{6.18.57,7.3}` 在 cache.nixos.org 都有预编译，安装是秒级。

### 配置要点

```nix
hardware.nvidia = {
  open = true;                  # Blackwell 只有 open 模块；>=560 必须显式设置
  branch = "latest";            # 615.78.08
  modesetting.enable = true;    # Wayland KMS（niri 必需）
  powerManagement.enable = true;# 休眠保留显存
  dynamicBoost.enable = true;   # Max-Q 动态功耗（nvidia-powerd）
  nvidiaSettings = true;
  videoAcceleration = true;     # VA-API
};
hardware.graphics.enable32Bit = true;   # lib32-nvidia-utils 对应
services.xserver.videoDrivers = [ "nvidia" ];
```

实测生效情况：

- `boot.extraModprobeConfig` 生成 `options nvidia-drm fbdev=1 modeset=1`
  和 `options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_UseKernelSuspendNotifiers=1`
- 615 分支用**内核 suspend notifier** 替代了 userspace 的
  `nvidia-suspend/resume/hibernate` 服务，所以只有 `nvidia-powerd.service`
- `hardware.nvidia.videoAcceleration` 默认 true，会带上 `nvidia-vaapi-driver`

### ⚠️ 必须打 patchelf workaround

**nixpkgs#576412 / patchelf#674**：patchelf 0.19.2 在**单次**调用里同时设置
`--interpreter` 和 `--set-rpath` 会生成重叠的 `LOAD` 段，`.dynamic` 落在只读页，
`ld.so` 写 `DT_DEBUG` 时 `SEGV_ACCERR`。`nvidia-x11` 的 builder 正是这么调用的，
结果 `nvidia-smi` / `nvidia-powerd` / `nvidia-cuda-mps-*` / `nvidia-debugdump`
**全部在 `main()` 之前段错误**（驱动本身正常，桌面和游戏不受影响）。

`modules/nvidia-patchelf-fix.nix` 用 `origBin/` 里的原始二进制重新打补丁，
并把 rpath 与 interpreter **拆成两次 patchelf 调用（先 rpath）**。

验证（在真机上有 GPU 的环境）：

```console
$ nix build .#nixosConfigurations.kotone.config.hardware.nvidia.package.bin
$ ./result/bin/nvidia-smi -L
GPU 0: NVIDIA GeForce RTX 5060 Laptop GPU (UUID: GPU-...)
```

等 nixpkgs 的 patchelf 升到含 NixOS/patchelf#672 的版本后，删掉该模块即可。

### VM 里的「安装」验证

VM 没有 NVIDIA 硬件，所以只安装不启用：

```nix
boot.extraModulePackages = [ config.boot.kernelPackages.nvidiaPackages.latest.open ];
environment.systemPackages = [
  config.boot.kernelPackages.nvidiaPackages.latest.out   # libnvidia-ml
  config.boot.kernelPackages.nvidiaPackages.latest.bin   # nvidia-smi
];
```

> 注意 `nvidia-x11` 的 `meta.outputsToInstall` 只有 `["bin"]`，
> 直接写 `nvidiaPackages.latest` 只会装 bin，**必须显式 `.out`**。

VM 内实测：

```console
$ modinfo nvidia | grep version
version:        615.78.08
$ nvidia-smi
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver.
# exit 9，符合预期（无 GPU）；打 workaround 前这里是 139 段错误
```

---

---

## Noctalia Greeter（声明式）

NixOS 上全部交给 nixpkgs 模块（`nixos/modules/services/display-managers/noctalia-greeter.nix`）：

```nix
services.displayManager.noctalia-greeter = {
  enable = true;
  settings = {
    session.default = "Niri";        # desktop entry 的 Name=
    cursor = { theme = "capitaine-cursors"; size = 24; };
    keyboard.layout = "us";
    clock.enabled = true;
    appearance.scheme = "Noctalia";
    # 真机额外：外接屏优先
    output = { name = "DP-1"; use_synced_settings = true; };
  };
  cursorTheme = { package = pkgs.capitaine-cursors; name = "capitaine-cursors"; };
};

# greetd 模块只建 greeter 用户，不给 DRM 权限
users.users.greeter.extraGroups = [ "video" "render" ];
```

模块自动完成的事：

| 动作 | 说明 |
|---|---|
| `services.greetd.enable` | `mkDefault true` |
| `default_session.command` | `mkDefault "${noctalia-greeter-session}"` |
| `default_session.user` | 由 greetd 模块 `mkDefault "greeter"` |
| `/var/lib/noctalia-greeter/` | tmpfiles `d`，属主 greeter:greeter，0750 |
| `/var/lib/noctalia-greeter/greeter.toml` | tmpfiles `L+` 指向 nix store 里生成的 TOML |
| `services.accounts-daemon` | `mkDefault true`（头像来源） |
| `security.polkit` | `mkDefault true` + `enablePkexecWrapper` |
| `passwordlessSyncUsers` | 非空时追加 polkit 规则，允许免密 Sync 外观 |

### 外观：对齐 Nyxuri 出厂默认

Nyxuri 的 greeter 模块（`nyxuri/modules/greeter.py`）**只写 greetd 配置和 polkit 规则，
不写样式**。样式来自 Noctalia Sync 写入的 `sync.toml`，而色板是 Noctalia 用
Material You 从壁纸推导的。

因此 `modules/greeter.nix` 直接复刻这条链路：

| 项 | 来源 |
|---|---|
| 壁纸 | Nyxuri 自带 `assets/wallpapers/lawson_fuji.webp`（3840x2160） |
| 色板 | matugen **4.2.0**（Nyxuri 实测版本）从该壁纸提取 |
| scheme | `scheme-content`（对应 Nyxuri `[theme] wallpaper_scheme = "m3-content"`） |
| mode | `dark`（夜景富士） |

```console
$ nix run nixpkgs#matugen -- image modules/greeter/lawson_fuji.webp \
    --source-color-index 0 --mode dark --type scheme-content --json hex -q
primary=#b4c5ff  surface=#121317  surface_variant=#444650
surface_container=#1f1f24  outline=#8f909b  error=#ffb4ab
```

生成结果落在 `modules/greeter/palette.json`（16 键，与 greeter 的
`ColorRole` 枚举一一对应）。

#### 两个坑

1. **调色板必须写在 `[appearance.palette]` 下**。直接写成 `[appearance]` 的子键会被
   greeter 当未知键忽略，日志里刷一屏 `unrecognized key 'appearance.primary'`，
   然后静默回退到内置配色。
2. **卡片颜色来自 `surface_variant`**。M3 深色下它是偏灰的 `#444650`，
   而 greeter 内置深色主题用的是 `#1e222a`，直接套会显得发灰。
   这里映射到 `surface_container`（`#1f1f24`），实测卡片渲染为 `#26262b`，
   与 Nyxuri 面板观感一致。

#### Nyxuri 样式定制清单 vs greeter 可用选项

Nyxuri 的界面定制集中在 `configs/noctalia/noctalia-config.toml`（292 行）和
`configs/niri/`。逐项对照 greeter 的 `[appearance]` 能力：

| Nyxuri 配置项 | 值 | greeter 对应 |
|---|---|---|
| `[theme] source` | `wallpaper` | 色板从壁纸提取 ✅ |
| `[theme] wallpaper_scheme` | `m3-content` | `--type scheme-content` ✅ |
| `[theme] mode` | `auto` | `theme_mode = "dark"`（夜景壁纸）✅ |
| `[theme] builtin` | `Ayu` | 未用（`scheme = "Synced"` 覆盖） |
| `[theme] community_palette` | `One Dark Two` | 未用（同上） |
| `[shell] font_family` | `Noto Sans CJK SC` | `appearance.font_family` ✅ |
| `[wallpaper] fill_mode` | `crop` | `appearance.wallpaper.fill_mode` ✅ |
| `[shell.greeter_sync] auto_sync` | `true` | N/A（NixOS 走声明式） |
| `[backdrop] blur_intensity` | `0.69` | ❌ greeter 不做背景模糊 |
| `[bar.bar] capsule_radius` | `80` | ❌ bar 专用 |
| `[bar.bar] font_family` | `JetBrains Mono` | ❌ bar 专用 |
| `[dock] radius` | `20` | ❌ dock 专用 |
| `configs/niri/layout.kdl` `geometry-corner-radius` | `12` | ❌ greeter 用自己的基准 × `corner_radius_scale`（1.0） |
| `[shell.panel] transparency_mode` | `soft` | ❌ panel 专用 |

**桌面侧**（greeter 无关，但属于 Nyxuri 样式定制）：

- 主题模板：`kitty` / `qt` / `starship`（builtin）+ NyxMellow fcitx5 皮肤、
  GTK3/GTK4 Material You `gtk.css`、niri `colors.kdl`、`~/.cache/nyxuri/palette.toml`
- 布局：bar `thickness = 36` / `scale = 1.1` / `panel_overlap = 12`、
  capsule 分组（`sysmon` + `ram`）、dock `radius = 20`、OSD `bottom_center` `scale = 0.9`
- 透明度：bar `background_opacity = 0` / `capsule_opacity = 0.79`、
  OSD `0.85`、`[backdrop] tint_intensity = 0`
- niri：`glow.kdl` 默认关焦点环 + 阴影 `softness 10 spread 4`，
  窗口圆角 `12` + `clip-to-geometry`
- 壁纸：`assets/wallpapers/lawson_fuji.webp`，目录 `~/图片/Wallpapers`，
  mpvpaper 插件支持视频壁纸

#### 实测截图对比

| 配置 | 卡片 | 强调色 | 背景 |
|---|---|---|---|
| 内置 `Noctalia` scheme | `#1e222a` 深蓝 | 黄 `#f9f945` | 纯色 |
| M3 `surface_variant` 直出 | `#4a4c55` 灰 | 蓝 `#b1c3fd` | lawson_fuji |
| **映射到 `surface_container`** | `#26262b` 深灰 | 蓝 `#b1c3fd` | lawson_fuji |

登录链路仍然正常：

```console
greetd[17944]: pam_unix(greetd:session): session opened for user kotone(uid=1000)
```

### 会话发现

greeter 从 `wayland-sessions` / `xsessions` 目录发现会话，搜索路径包括
`/run/current-system/sw/share` 和 `XDG_DATA_DIRS` 的每一项。

`programs.niri.enable` 会设置 `services.displayManager.sessionPackages = [ niri ]`，
NixOS 把这些包里的 desktop 文件用 `lndir` 汇总成一个 `desktops` 派生，
再通过 `environment.sessionVariables.XDG_DATA_DIRS` 暴露出来：

```console
$ echo $XDG_DATA_DIRS
/nix/store/...-desktops/share:/home/kotone/.local/share/flatpak/exports/share:...
$ ls /nix/store/...-desktops/share/wayland-sessions/
niri.desktop
$ grep Name= /nix/store/...-desktops/share/wayland-sessions/niri.desktop
Name=Niri
```

所以 `session.default = "Niri"`（大小写不敏感，也接受文件名 `niri`）。

### VM 实测

在 QEMU 里完整跑通（`hosts/kotone-vm` 额外设了 `user.default = "kotone"` 方便自动化）：

```console
$ systemctl is-active greetd
active
$ pgrep -af noctalia-greeter
16411 dbus-run-session -- env ... noctalia-greeter-compositor --
16637 .../bin/noctalia-greeter
$ id greeter
uid=998(greeter) gid=998(greeter) 组=998(greeter),26(video),303(render)
$ journalctl -b | grep -i 'noctalia-greeter\['
[INF] [gl] initialized EGL 1.5 with shared root context
[INF] [render] OpenGL ES renderer="virgl (NVIDIA GeForce RTX 5060 Laptop GPU/PCIe/SSE2)"
[INF] [greetd] connected to greetd at /run/greetd-16220.sock
[INF] [seat] keyboard: bound / pointer: bound
[INF] [wayland] output 'Virtual-1' ready 1256x1331 at (0,0) scale=2
[INF] [greeter-surface] AccountsService: 1 cached user(s), 1 after filters
[INF] [greeter-window] presented first frame 628x665 logical (1256x1330 buffer, scale=2.00)
[INF] [greeter] greeter initialized (1 view(s))
```

登录链路（`sendkey` 输入密码）：

```console
greetd[17975]: pam_unix(greetd:session): session opened for user kotone(uid=1000)
# 随后 niri --session + noctalia 起来
```

界面截图确认：时钟、AccountsService 头像、密码框、会话选择器显示 **Niri**、
Noctalia logo、右下角键盘/重启/电源按钮。

### 渲染后端

| 显示设备 | 渲染器 | 首帧耗时 |
|---|---|---|
| `virtio-vga-gl` + `-display gtk,gl=on` | virgl (Mesa) | ~67 ms |
| `virtio-vga`（无 3D） | pixman 软件回退 | ~349 ms |

**greeter 有 pixman 回退，所以没有 GL 也能显示**（但 niri 登录后需要 GL）。
截图只能用 `-display none -vnc :1` + 普通 `virtio-vga`——`gl=on` 时
QEMU 的 `screendump` 会报 `Error: no surface`。

#---

## 桌面 shell 样式（Noctalia bar / panel / dock / OSD）

greeter 只消费「色板 + 壁纸 + 字体 + 圆角」，bar/panel 这些是 **Noctalia 自己渲染**的，
必须把 Nyxuri 的 `configs/noctalia/` 部署到 `~/.config/noctalia/` 才会生效。

`home/noctalia.nix` 做的就是这件事：

| 源（Nyxuri） | 目标 |
|---|---|
| `configs/noctalia/noctalia-config.toml` | `~/.config/noctalia/noctalia-config.toml`（`/home/user` → `$HOME`） |
| `configs/noctalia/templates/*` | `~/.config/noctalia/templates/*` |
| `configs/noctalia/{wallpaper-hook.sh,mpvpaper-sync.sh,mpv-hook.lua}` | `~/.config/noctalia/` |
| `assets/fcitx5/nyxmellow/templates/*` | `~/.local/share/fcitx5/themes/nyxmellow/templates/*` |

未纳入：`tools/`（orbit launcher / translate / wallpaper-picker），与 bar/panel 样式无关。

### 对齐后的实际效果

| 项 | Nyxuri 配置 | 实测 |
|---|---|---|
| bar 形态 | `capsule = true`、`background_opacity = 0`、`capsule_radius = 80` | 浮动胶囊，无整条背景 ✅ |
| bar 内容 | `start = [launcher, workspaces, group:g1]`、`center = [clock]`、`end = [media, volume, tray, notifications, session]` | 搜索/工作区/sysmon+ram 组 + 居中时钟 + 右侧四钮 ✅ |
| bar 字体 | `font_family = "JetBrains Mono"`、`font_weight = 600` | 时钟等宽 ✅ |
| 时钟格式 | `[widget.clock] format = "{:%m/%d/%y %H:%M}"` | `10/25/26 01:34` ✅ |
| 尺寸 | `thickness = 36`、`scale = 1.1`、`margin_ends = 14`、`margin_edge = 10` | ✅ |
| panel | `control_center_placement = "floating"`、`position = "top_right"`、`transparency_mode = "soft"` | 右上浮动半透明面板 ✅ |
| OSD | `position = "bottom_center"`、`scale = 0.9`、`background_opacity = 0.85` | 已部署（VM 里 `volume-osd` 报 `no default output`，未截到） |
| dock | `enabled = true`、`radius = 20`、`smart_auto_hide = true` | 未固定应用，空 dock 不渲染 |

### 两处必要补充

1. **壁纸**：Nyxuri 的 `[wallpaper]` 只给了 `directory` 和 `fill_mode`，具体用哪张是
   用户在 picker 里选的（存 `~/.local/state/noctalia/settings.toml`）。
   为了让桌面和 greeter 一致，`home/noctalia.nix` 在配置末尾追加：

   ```toml
   [wallpaper.default]
   path = "/nix/store/...-lawson_fuji.webp"
   ```

2. **首次运行向导**：Noctalia 靠 `~/.local/state/noctalia/.setup-complete` 判断是否
   首次启动，缺失就弹「欢迎使用 Noctalia」遮住桌面。用 activation 提前 touch 掉。

### 验证方式

`gl=on` 时 QEMU 的 `screendump` 不可用（`Error: no surface`），所以截图改成
**VM 内 grim**：

```console
$ export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1
$ grim /tmp/desk.png
$ noctalia msg panel-open control-center && grim /tmp/panel.png
```

（`grim` 已加进 `home/packages.nix`。）

## 已知限制

**greeter**

1. **`greeter.toml` 会被 activation 覆盖**：模块用 tmpfiles `L+` 每次激活重写，
   上游也承认里面混了「最近使用的会话」这类状态。要持久化选择只能靠
   `sync.toml`（greeter 自己写的可写文件）。
2. **`user.default` 只适合测试**：真机不要设，否则每次开机都跳到某个用户的密码步骤。
3. **`greeter` 用户必须手动加 `video`/`render` 组**：greetd 模块只建用户，
   不给 DRM 权限；CachyOS 的包脚本会加 `video`，NixOS 需要自己写。

**桌面**

4. **`noctalia` 版本**：实测 nixpkgs unstable 已是 5.3.0，与本机一致。
   需要更新时仍可换官方 flake。
5. **`effects.kdl` 由 `toggle-eyecare.sh` 管理**，home-manager 只在缺失时创建，
   不会每次 switch 重置护眼状态。
6. **`fcitx5/config` 与 `profile` 用可写副本**（activation 里 `install`），
   不是 nix store 符号链接 —— 因为 fcitx5 会回写这两个文件。
7. **VM 和真机都用 `noctalia-greeter`**（VM 额外设 `user.default` 便于自动化测试）。
8. **`display.kdl` 按 host 生成**：VM 留空自动探测；真机用 `DP-1`。

---

## CI（GitHub Actions）

`.github/workflows/ci.yml`，五层递进：

| Job | 做什么 | 耗时 | 能抓到什么 |
|---|---|---|---|
| `vendor` | `materialize.sh --check` | ~20 s | `vendor/` 被手改 / 忘记刷新 |
| `lint` | `nix flake check` | ~40 s | 格式、shell、Lua 语法 |
| `eval` | `nix eval …toplevel.drvPath`（矩阵：两个 host） | ~1 min | 选项拼错、包不存在、模块冲突、assertion |
| `build` | `nix build …kotone-vm…toplevel` | ~10 min | 真的编不过的包 |
| `vm-test` | 构建 disko 镜像 → QEMU 启动 → 等登录提示 | ~15 min | 镜像能不能开机 |

**真机 `kotone` 只求值不构建** —— 它要现编 NVIDIA 内核模块，CI 里不划算。

**`vm-test` 只在 `main` 和手动触发时跑**（PR 上太慢）。它会真的把
`nixos-vm.raw` 启动一遍，等到串口出现 `login:` 才算通过；
有 KVM 约 1 分钟，没有就退回 TCG 约 8 分钟。

`flake.nix` 的 `checks` 只放轻量静态检查（格式 / shellcheck / Lua 语法），
整机闭包不进 checks，否则 `nix flake check` 会拖入内核编译。

本地等价：

```bash
./pipeline/materialize.sh --check
nix flake check
nix eval --raw .#nixosConfigurations.kotone.config.system.build.toplevel.drvPath
nix build .#nixosConfigurations.kotone-vm.config.system.build.toplevel
# 本地起 VM 见上面「从零构建」
```

**改 CI 前先看这两个文件里的注释**：可调项（host 矩阵、runner 标签、
Cachix 缓存开关）都标了「改这里」。action 全部按 commit SHA 固定，
由 `.github/dependabot.yml` 每周提 PR 升级。
