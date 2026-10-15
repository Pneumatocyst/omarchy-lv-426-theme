#!/usr/bin/env bash
# LV-426: low battery triggers the Nostromo emergency destruct warning.
# Called with the current battery percentage.
set -uo pipefail
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null) == lv-426 ]] || exit 0
pct=${1:-?}
(pw-play --volume 0.5 "$HOME/.config/omarchy/themes/lv-426/sounds/klaxon.wav" >/dev/null 2>&1 &)
omarchy-notification-send -u critical -g 󰂃 "EMERGENCY DESTRUCT SYSTEM" \
  "POWER RESERVES AT ${pct}%. CONNECT CHARGER. THE OPTION TO OVERRIDE DETONATION PROCEDURE EXPIRES SOON." >/dev/null 2>&1
exit 0
