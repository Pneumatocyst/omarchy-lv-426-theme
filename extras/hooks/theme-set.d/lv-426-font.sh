#!/usr/bin/env bash
# LV-426 uses the IBM 3270 mainframe font. Selecting LV-426 switches to it and
# remembers the previous font; selecting any other theme restores that font.
set -uo pipefail
retro="3270 Nerd Font Mono"
saved="$HOME/.local/state/lv-426/previous-font"
theme=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
current=$(omarchy-font-current 2>/dev/null)

if [[ $theme == lv-426 ]]; then
  fc-list | grep -Fqi -- "$retro" || exit 0
  if [[ $current != "$retro" ]]; then
    mkdir -p "${saved%/*}"
    printf '%s\n' "$current" > "$saved"
    omarchy-font-set "$retro" >/dev/null
  fi
elif [[ $current == "$retro" && -s $saved ]]; then
  omarchy-font-set "$(< "$saved")" >/dev/null && rm -f "$saved"
fi
exit 0
