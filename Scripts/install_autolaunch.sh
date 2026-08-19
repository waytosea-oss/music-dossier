#!/bin/zsh
# 安装/卸载"打开 Music 时自动启动"的 LaunchAgent。
#   Scripts/install_autolaunch.sh          安装
#   Scripts/install_autolaunch.sh --remove 卸载
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LABEL="$BUNDLE_ID.autolaunch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN_DIR="$SUPPORT_DIR/bin"

if [[ "${1:-}" == "--remove" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "已卸载 $LABEL"
  exit 0
fi

mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents"
cp "$SCRIPT_DIR/autolaunch_watcher.sh" "$BIN_DIR/autolaunch_watcher.sh"
chmod +x "$BIN_DIR/autolaunch_watcher.sh"
cat >"$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$BIN_DIR/autolaunch_watcher.sh</string>
    <string>$APP_BUNDLE</string>
  </array>
  <key>StartInterval</key><integer>15</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>$SUPPORT_DIR/autolaunch.err.log</string>
</dict>
</plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "已安装 $LABEL：打开 Music 时会自动启动「$APP_NAME」"
