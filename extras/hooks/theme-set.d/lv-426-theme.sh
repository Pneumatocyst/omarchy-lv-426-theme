#!/usr/bin/env bash
# Starts only LV-426; its watcher exits immediately when another theme is chosen.
set -euo pipefail
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null) == lv-426 ]] || exit 0
program="$HOME/.config/omarchy/themes/lv-426/animation/wallpaper.py"
log="${XDG_RUNTIME_DIR:-/tmp}/lv-426-$(id -u).log"
# The living wallpaper needs its graded photo; without one Omarchy's static
# background from backgrounds/ stays in place.
if [[ -f ${program%/*}/photo.png ]]; then
  nohup env GSK_RENDERER=cairo python3 "$program" > "$log" 2>&1 < /dev/null &
fi
# Notification chirp watcher (exits by itself when the theme changes).
nohup setsid "$HOME/.config/omarchy/themes/lv-426/bin/lv426-notify-chirp" >/dev/null 2>&1 < /dev/null &
