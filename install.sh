#!/bin/bash
# Music Dossier 一行安装（小白版）：
#   curl -fsSL https://raw.githubusercontent.com/waytosea-oss/music-dossier/main/install.sh | bash
# 做的事：下载最新预编译版 → 解除 macOS 隔离 → 放进「应用程序」→ 打开。
set -euo pipefail

REPO="waytosea-oss/music-dossier"
APP_NAME="Music Dossier"
DEST="/Applications/$APP_NAME.app"

echo ""
echo "🎵 Music Dossier 安装程序"
echo "──────────────────────────"

if [ "$(uname -m)" != "arm64" ]; then
  echo "❌ 预编译版目前只支持 Apple Silicon（M 系列）的 Mac。"
  echo "   Intel Mac 请用源码安装：git clone 仓库后运行 Scripts/install.sh（需要 Xcode 命令行工具）。"
  exit 1
fi

# 1. 找最新 Release 里的 zip
echo "① 正在获取最新版本…"
API="https://api.github.com/repos/$REPO/releases/latest"
URL="$(curl -fsSL "$API" | /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)
for a in d.get("assets",[]):
    if a["name"].endswith(".zip"):
        print(a["browser_download_url"]); break
' )"
if [ -z "$URL" ]; then
  echo "❌ 没有找到可下载的版本。请到 https://github.com/$REPO/releases 手动下载。" >&2
  exit 1
fi
echo "   $URL"

# 2. 下载并解压
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "② 正在下载…"
curl -fL --progress-bar "$URL" -o "$TMP/app.zip"
echo "③ 正在解压…"
ditto -x -k "$TMP/app.zip" "$TMP/unpacked"
SRC="$(/usr/bin/find "$TMP/unpacked" -maxdepth 2 -name "*.app" -print -quit)"
[ -n "$SRC" ] || { echo "❌ 压缩包里没有找到应用。" >&2; exit 1; }

# 3. 解除隔离标记（这样双击不会被 macOS 拦下）
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

# 4. 安装到「应用程序」
echo "④ 正在安装到 /Applications …"
if [ -d "$DEST" ]; then
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  pkill -f "$DEST/Contents/MacOS" 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
fi
ditto "$SRC" "$DEST"

# 5. 打开
echo "⑤ 完成，正在打开…"
open "$DEST"

echo ""
echo "✅ 安装完成！"
echo ""
echo "接下来只差一步："
echo "  应用会弹出「设置」窗口 → 选一个 AI 服务商（推荐 DeepSeek，便宜）"
echo "  → 点「去申请 Key」注册并复制 API Key → 粘贴 → 点「测试连接」→ 保存。"
echo ""
echo "然后打开 Apple Music 放一首歌，小窗就会开始写档案了。"
