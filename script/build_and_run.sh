#!/usr/bin/env bash
# 开发用：停掉旧实例 → 重新打包 → 打开。 用法: script/build_and_run.sh [run|--debug|--logs|--verify]
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/Scripts" REPO_ROOT="$ROOT_DIR" source "$ROOT_DIR/Scripts/common.sh"
APP_PROCESS="$EXECUTABLE_NAME"
PACKAGE_SCRIPT="$ROOT_DIR/Scripts/package_app_bundle.sh"

build_app() { /bin/zsh "$PACKAGE_SCRIPT" "$APP_BUNDLE"; }
stop_app()  { /usr/bin/pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_PROCESS" >/dev/null 2>&1 || true; }
open_app()  { /usr/bin/open "$APP_BUNDLE"; }

case "$MODE" in
  run) stop_app; build_app; open_app ;;
  --debug|debug) stop_app; build_app; lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_PROCESS" ;;
  --logs|logs) stop_app; build_app; open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_PROCESS\"" ;;
  --verify|verify) stop_app; build_app; open_app; sleep 2; /usr/bin/pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_PROCESS" >/dev/null ;;
  *) echo "usage: $0 [run|--debug|--logs|--verify]" >&2; exit 2 ;;
esac
