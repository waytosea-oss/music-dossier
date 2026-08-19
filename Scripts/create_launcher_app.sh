#!/bin/zsh
# 生成一个桌面启动器（双击即打开主应用），例如：
#   Scripts/create_launcher_app.sh "$HOME/Desktop/启动 Music Dossier.app"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
TARGET_APP="${1:?用法: create_launcher_app.sh <启动器.app 路径> [主应用.app 路径]}"
TARGET_BUNDLE="${2:-$APP_BUNDLE}"
LAUNCHER_NAME="$(basename "$TARGET_APP" .app)"
BUNDLE_SUFFIX="$(printf '%s' "$LAUNCHER_NAME" | LC_ALL=C tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
[[ -z "$BUNDLE_SUFFIX" ]] && BUNDLE_SUFFIX="launcher"
MACOS_DIR="$TARGET_APP/Contents/MacOS"
RESOURCES_DIR="$TARGET_APP/Contents/Resources"
ICON_ICNS="$REPO_ROOT/Assets/AppIcon/MusicDossier.icns"
ICON_PNG="$REPO_ROOT/Assets/AppIcon/MusicDossierIcon.png"

rm -rf "$TARGET_APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cat >"$MACOS_DIR/MusicDossierLauncher" <<LAUNCHER
#!/bin/zsh
set -u
TARGET_BUNDLE="$TARGET_BUNDLE"
if [[ ! -d "\$TARGET_BUNDLE" ]]; then
  /usr/bin/osascript -e 'display alert "启动失败" message "没有找到 $TARGET_BUNDLE。请先运行 Scripts/install.sh 打包主应用。" as critical buttons {"好"} default button "好"' >/dev/null 2>&1 || true
  exit 1
fi
/usr/bin/open "\$TARGET_BUNDLE"
LAUNCHER
chmod +x "$MACOS_DIR/MusicDossierLauncher"
cp "$ICON_ICNS" "$RESOURCES_DIR/MusicDossier.icns"
cp "$ICON_PNG" "$RESOURCES_DIR/MusicDossierIcon.png"
cat >"$TARGET_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>$LAUNCHER_NAME</string>
  <key>CFBundleExecutable</key><string>MusicDossierLauncher</string>
  <key>CFBundleIconFile</key><string>MusicDossier</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.launcher.$BUNDLE_SUFFIX</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$LAUNCHER_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
swift -e "import AppKit
guard let image = NSImage(contentsOfFile: \"$ICON_PNG\") else { fatalError(\"missing icon image\") }
_ = NSWorkspace.shared.setIcon(image, forFile: \"$TARGET_APP\", options: [])" 2>/dev/null || true
touch "$TARGET_APP"
codesign --force --deep -s - "$TARGET_APP" >/dev/null 2>&1 || true
echo "$TARGET_APP"
