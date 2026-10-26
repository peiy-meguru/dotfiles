# vendor/ —— 物化的上游文件

**不要手改这个目录。** 它由 `pipeline/materialize.sh` 生成。

| 项 | 值 |
|---|---|
| 上游 | [ech678/Nyxuri](https://github.com/ech678/Nyxuri) |
| 版本 | `ebafe03c9bdf1291eeb83d0f8c368d40a63ccdfd` |
| 生成方式 | `./pipeline/materialize.sh` |

## 内容

| 路径 | 来源 | 处理 |
|---|---|---|
| `noctalia/` | `configs/noctalia/` | 去掉 `README.md` / `.module.toml` / `tools/`，按序打 `pipeline/patches/*.patch` |
| `nyxmellow/` | `assets/fcitx5/nyxmellow/templates/` | 原样 |
| `lawson_fuji.webp` | `assets/wallpapers/lawson_fuji.webp` | 原样 |

## 为什么物化

让 NixOS 配置**只依赖 nixpkgs**：干净 clone 下来就能从 0 构建，
不需要联网拉第三方仓库，上游改动也不会悄悄影响构建。

## 刷新

```bash
./pipeline/materialize.sh --rev <新的 commit sha>   # 换版本
./pipeline/materialize.sh                          # 同版本重新生成
./pipeline/materialize.sh --check                  # 校验是否与 rev 一致（CI 跑这个）
```
