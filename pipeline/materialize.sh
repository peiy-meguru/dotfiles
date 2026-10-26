#!/usr/bin/env bash
# ==============================================================================
# 把 Nyxuri 里「本配置真正用到的那部分」物化到 vendor/
#
# 为什么要有这一步
#   上游 Nyxuri 不在 nixpkgs 里。如果让 flake 直接依赖
#   github:ech678/Nyxuri，那么每次构建都要联网拉那个仓库，
#   而且上游一改（或被删）构建就跟着变。
#   物化之后：vendor/ 是普通文件，构建只依赖 nixpkgs，从 0 也能编。
#
# 用法
#   ./pipeline/materialize.sh                 # 按 vendor/source.json 的 rev 重新物化
#   ./pipeline/materialize.sh --rev <sha>     # 换版本（会更新 source.json）
#   ./pipeline/materialize.sh --check         # 只校验 vendor/ 是否与 rev 一致（CI 用）
#
# 物化内容（约 600 KB，壁纸占 504 KB）
#   vendor/noctalia/        configs/noctalia 去掉 README/.module.toml/tools，
#                           并打上 pipeline/patches/noctalia-idle.patch
#   vendor/nyxmellow/       assets/fcitx5/nyxmellow/templates/
#   vendor/lawson_fuji.webp assets/wallpapers/lawson_fuji.webp
#
# 不在物化范围内
#   palette.json —— 由壁纸经 matugen 确定性生成，构建期算（matugen 在 nixpkgs 里）
#   windows-pointer 插件 —— 源在 pipeline/windows-pointer/，本来就在仓库内
# ==============================================================================
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

SOURCE_JSON=vendor/source.json
PATCH=pipeline/patches/noctalia-idle.patch

MODE=materialize
REV=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --rev)   REV=${2:?--rev 需要参数}; shift 2 ;;
        --check) MODE=check; shift ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

# 没指定 --rev 就用 source.json 里记的
if [[ -z $REV ]]; then
    [[ -f $SOURCE_JSON ]] || { echo "✗ 缺少 $SOURCE_JSON，请先 --rev <sha>" >&2; exit 1; }
    REV=$(sed -n 's/.*"rev": *"\([^"]*\)".*/\1/p' "$SOURCE_JSON")
fi
[[ -n $REV ]] || { echo "✗ 无法确定 rev" >&2; exit 1; }

REPO=ech678/Nyxuri
URL="https://github.com/$REPO/archive/$REV.tar.gz"

echo "=== 拉取 $REPO@${REV:0:12} ==="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 3 --max-time 180 "$URL" -o "$TMP/src.tar.gz"
tar xzf "$TMP/src.tar.gz" -C "$TMP"
SRC="$TMP/Nyxuri-$REV"
[[ -d $SRC ]] || { echo "✗ 解压后找不到 $SRC" >&2; exit 1; }

echo "=== 提取到 $TMP/out ==="
OUT="$TMP/out"
mkdir -p "$OUT/noctalia" "$OUT/nyxmellow"

# configs/noctalia：只留界面相关，剔除文档 / 部署清单 / 独立脚本
cp -r "$SRC/configs/noctalia/." "$OUT/noctalia/"
rm -rf "$OUT/noctalia/README.md" "$OUT/noctalia/.module.toml" "$OUT/noctalia/tools"

# 本地改动以补丁形式叠加（-p3 剥掉 a/configs/noctalia/ 前缀）
if [[ -s $PATCH ]]; then
    patch -p3 -s -d "$OUT/noctalia" < "$PATCH"
fi

cp -r "$SRC/assets/fcitx5/nyxmellow/templates/." "$OUT/nyxmellow/"
cp "$SRC/assets/wallpapers/lawson_fuji.webp" "$OUT/lawson_fuji.webp"

# ------------------------------------------------------------------------------
# --check：把结果和现有 vendor/ 比，不一致就失败（CI 用）
# ------------------------------------------------------------------------------
if [[ $MODE == check ]]; then
    if diff -r --exclude=source.json --exclude=MANIFEST.md "$OUT" vendor >/dev/null 2>&1; then
        echo "✓ vendor/ 与 $REPO@${REV:0:12} 一致"
        exit 0
    fi
    echo "✗ vendor/ 与 $REPO@${REV:0:12} 不一致" >&2
    diff -r --exclude=source.json --exclude=MANIFEST.md "$OUT" vendor >&2 || true
    echo >&2
    echo "修复：./pipeline/materialize.sh" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 正式物化：替换 vendor/ 并写元数据
# ------------------------------------------------------------------------------
echo "=== 写入 vendor/ ==="
rm -rf vendor
mkdir -p vendor
cp -r "$OUT/." vendor/

cat > "$SOURCE_JSON" <<EOF
{
  "repo": "$REPO",
  "rev": "$REV",
  "url": "https://github.com/$REPO",
  "generatedBy": "pipeline/materialize.sh",
  "note": "自动生成，勿手改。刷新：./pipeline/materialize.sh --rev <sha>"
}
EOF

cat > vendor/MANIFEST.md <<EOF
# vendor/ —— 物化的上游文件

**不要手改这个目录。** 它由 \`pipeline/materialize.sh\` 生成。

| 项 | 值 |
|---|---|
| 上游 | [$REPO](https://github.com/$REPO) |
| 版本 | \`$REV\` |
| 生成方式 | \`./pipeline/materialize.sh\` |

## 内容

| 路径 | 来源 | 处理 |
|---|---|---|
| \`noctalia/\` | \`configs/noctalia/\` | 去掉 \`README.md\` / \`.module.toml\` / \`tools/\`，打 \`pipeline/patches/noctalia-idle.patch\` |
| \`nyxmellow/\` | \`assets/fcitx5/nyxmellow/templates/\` | 原样 |
| \`lawson_fuji.webp\` | \`assets/wallpapers/lawson_fuji.webp\` | 原样 |

## 为什么物化

让 NixOS 配置**只依赖 nixpkgs**：干净 clone 下来就能从 0 构建，
不需要联网拉第三方仓库，上游改动也不会悄悄影响构建。

## 刷新

\`\`\`bash
./pipeline/materialize.sh --rev <新的 commit sha>   # 换版本
./pipeline/materialize.sh                          # 同版本重新生成
./pipeline/materialize.sh --check                  # 校验是否与 rev 一致（CI 跑这个）
\`\`\`
EOF

echo "✓ 完成"
du -sh vendor
find vendor -type f | sort | sed 's/^/  /'
