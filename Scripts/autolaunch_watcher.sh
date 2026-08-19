#!/bin/zsh
# Music.app 一打开就拉起 Music Dossier；每个 Music 会话只拉一次（手动关掉小窗后不会反复弹）。
# 由 LaunchAgent 每 15 秒调用一次（见 Scripts/install_autolaunch.sh）。第一个参数是主应用 .app 路径。
set -u
APP="${1:-/Applications/Music Dossier.app}"
STATE="$HOME/Library/Application Support/MusicDossier/autolaunch.state"

MUSIC_PID="$(/usr/bin/pgrep -x Music | /usr/bin/head -1)"
if [[ -z "$MUSIC_PID" ]]; then
  [[ -f "$STATE" ]] && /bin/rm -f "$STATE"
  exit 0
fi
LAST="$(/bin/cat "$STATE" 2>/dev/null || true)"
[[ "$LAST" == "$MUSIC_PID" ]] && exit 0
if ! /usr/bin/pgrep -f "$APP/Contents/MacOS/MusicDossierApp" >/dev/null; then
  [[ -d "$APP" ]] && /usr/bin/open -g "$APP"
fi
/bin/echo "$MUSIC_PID" > "$STATE"
