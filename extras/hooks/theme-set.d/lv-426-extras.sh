#!/usr/bin/env bash
# LV-426 extras: MU-TH-UR screensaver art and a terminal chirp when the theme
# comes online. Selecting any other theme restores the previous screensaver.
set -uo pipefail
theme_dir="$HOME/.config/omarchy/themes/lv-426"
state="$HOME/.local/state/lv-426"
branding="$HOME/.config/omarchy/branding/screensaver.txt"
saved="$state/previous-screensaver.txt"
selected=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)

if [[ $selected == lv-426 ]]; then
  mkdir -p "$state" "${branding%/*}"
  if ! cmp -s "$branding" "$theme_dir/screensaver.txt"; then
    [[ -f $branding ]] && cp "$branding" "$saved"
    cp "$theme_dir/screensaver.txt" "$branding"
  fi
  (pw-play --volume 0.4 "$theme_dir/sounds/mother.wav" >/dev/null 2>&1 &)
  omarchy-notification-send -g 󰚩 "MU-TH-UR 6000" "INTERFACE 2037 READY FOR INQUIRY" >/dev/null 2>&1
else
  # Leaving LV-426: switch CRT mode off if it was on.
  "$theme_dir/bin/lv426-crt" off >/dev/null 2>&1
fi
if [[ $selected != lv-426 && -f $saved ]] && cmp -s "$branding" "$theme_dir/screensaver.txt"; then
  # Only restore if the LV-426 art is still in place (don't clobber later edits).
  mv "$saved" "$branding"
fi
exit 0
