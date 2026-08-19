#!/bin/zsh
# 一键安装：检查依赖 → 编译打包到 /Applications → 写默认配置 → 可选桌面启动器与自动启动。
#   Scripts/install.sh                 基本安装
#   Scripts/install.sh --launcher      同时在桌面放一个启动器
#   Scripts/install.sh --autolaunch    同时安装"打开 Music 自动启动"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "== Music Dossier 安装 =="
command -v swift >/dev/null || { echo "缺少 swift：请先安装 Xcode 或 Xcode Command Line Tools（xcode-select --install）" >&2; exit 1; }
CLAUDE_BIN="$(command -v claude || true)"
[[ -z "$CLAUDE_BIN" && -x "$HOME/.local/bin/claude" ]] && CLAUDE_BIN="$HOME/.local/bin/claude"
if [[ -z "$CLAUDE_BIN" ]]; then
  echo "⚠️  没找到 claude（Claude Code CLI）。应用能启动，但生成档案需要它：https://docs.anthropic.com/claude-code" >&2
else
  echo "claude: $CLAUDE_BIN"
fi

"$SCRIPT_DIR/package_app_bundle.sh" "$APP_BUNDLE"

mkdir -p "$SUPPORT_DIR"
if [[ ! -f "$SUPPORT_DIR/config.json" ]]; then
  cp "$REPO_ROOT/config.example.json" "$SUPPORT_DIR/config.json"
  echo "已写入默认配置：$SUPPORT_DIR/config.json"
fi

for arg in "$@"; do
  case "$arg" in
    --launcher) "$SCRIPT_DIR/create_launcher_app.sh" "$HOME/Desktop/启动 $APP_NAME.app" "$APP_BUNDLE" ;;
    --autolaunch) "$SCRIPT_DIR/install_autolaunch.sh" ;;
  esac
done

echo
echo "完成：$APP_BUNDLE"
echo "首次启动时 macOS 会询问「控制 Music」的自动化权限，请点允许。"
echo "打开：open \"$APP_BUNDLE\""
