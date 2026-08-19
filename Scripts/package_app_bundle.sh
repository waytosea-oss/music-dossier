#!/bin/zsh
# 编译并打包成 .app（默认 /Applications/Music Dossier.app）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
TARGET_APP="${1:-$APP_BUNDLE}"
ICON_ICNS="$REPO_ROOT/Assets/AppIcon/MusicDossier.icns"
ICON_PNG="$REPO_ROOT/Assets/AppIcon/MusicDossierIcon.png"
PLIST_PATH="$TARGET_APP/Contents/Info.plist"
MACOS_DIR="$TARGET_APP/Contents/MacOS"
RESOURCES_DIR="$TARGET_APP/Contents/Resources"

cd "$REPO_ROOT"
mkdir -p "$SCRATCH_PATH"
echo "→ swift build ($EXECUTABLE_NAME) …"
swift build -c release --scratch-path "$SCRATCH_PATH" --product "$EXECUTABLE_NAME" >/tmp/music_dossier_build.log 2>&1 || {
  echo "构建失败，日志：/tmp/music_dossier_build.log" >&2; tail -20 /tmp/music_dossier_build.log >&2; exit 1; }

BUILD_DIR="$(swift build -c release --scratch-path "$SCRATCH_PATH" --show-bin-path)"
BINARY_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
[[ -x "$BINARY_PATH" ]] || { echo "找不到产物 $BINARY_PATH" >&2; exit 1; }

rm -rf "$TARGET_APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_ICNS" "$RESOURCES_DIR/MusicDossier.icns"
cp "$ICON_PNG" "$RESOURCES_DIR/MusicDossierIcon.png"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key><string>MusicDossier</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSAppleEventsUsageDescription</key><string>$APP_NAME 需要读取 Music.app 的当前曲目与封面，用来生成歌曲档案页面。</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

touch "$TARGET_APP"
codesign --force --deep -s - "$TARGET_APP" >/tmp/music_dossier_codesign.log 2>&1 || true
echo "$TARGET_APP"
