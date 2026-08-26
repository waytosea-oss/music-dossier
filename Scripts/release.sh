#!/bin/zsh
# 出一个 GitHub Release：通用二进制 .app → zip → gh release create
# 用法：Scripts/release.sh v0.2.0 "发布说明"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
VERSION="${1:?用法: release.sh vX.Y.Z [说明]}"
NOTES="${2:-Music Dossier $VERSION}"

STAGE="$(mktemp -d)/Music Dossier.app"
# 本机仅 CLT，暂发 arm64（Apple Silicon）版；Intel 用户用源码安装
MUSIC_DOSSIER_APP_NAME="Music Dossier" MUSIC_DOSSIER_BUNDLE_ID="app.musicdossier.desktop" "$SCRIPT_DIR/package_app_bundle.sh" "$STAGE"

lipo -info 2>/dev/null || true; file "$STAGE/Contents/MacOS/MusicDossierApp"

ZIP="/tmp/MusicDossier-$VERSION-arm64.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$STAGE" "$ZIP"
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1))"

cd "$REPO_ROOT"
gh release create "$VERSION" "$ZIP" --title "Music Dossier $VERSION" --notes "$NOTES"
echo "✅ 已发布 $VERSION"
