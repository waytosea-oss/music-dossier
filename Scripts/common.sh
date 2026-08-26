#!/bin/zsh
# 公共变量。可用 Scripts/local.env（不入库）覆盖：
#   MUSIC_DOSSIER_APP_NAME="My Music Dossier"
#   MUSIC_DOSSIER_BUNDLE_ID="com.example.musicdossier"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
_PRESET_APP_NAME="${MUSIC_DOSSIER_APP_NAME:-}"
_PRESET_BUNDLE_ID="${MUSIC_DOSSIER_BUNDLE_ID:-}"
[[ -f "$REPO_ROOT/Scripts/local.env" ]] && source "$REPO_ROOT/Scripts/local.env"
[[ -n "$_PRESET_APP_NAME" ]] && MUSIC_DOSSIER_APP_NAME="$_PRESET_APP_NAME"
[[ -n "$_PRESET_BUNDLE_ID" ]] && MUSIC_DOSSIER_BUNDLE_ID="$_PRESET_BUNDLE_ID"

APP_NAME="${MUSIC_DOSSIER_APP_NAME:-Music Dossier}"
BUNDLE_ID="${MUSIC_DOSSIER_BUNDLE_ID:-app.musicdossier.desktop}"
APP_BUNDLE="${MUSIC_DOSSIER_APP_BUNDLE:-/Applications/$APP_NAME.app}"
EXECUTABLE_NAME="MusicDossierApp"
SCRATCH_PATH="${MUSIC_DOSSIER_SWIFTPM_SCRATCH:-$HOME/Library/Caches/MusicDossier/SwiftPMBuild}"
SUPPORT_DIR="$HOME/Library/Application Support/MusicDossier"
