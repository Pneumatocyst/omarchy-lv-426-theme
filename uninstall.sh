#!/usr/bin/env bash
# Removes everything install.sh added. Pick another theme first so the LV-426
# hooks restore your previous font and screensaver art.
set -uo pipefail
omarchy="$HOME/.config/omarchy"

if [[ $(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null) == lv-426 ]]; then
  echo "Switch to another theme first (omarchy theme set <name>), then rerun."
  exit 1
fi

if omarchy plugin list 2>/dev/null | grep -q '^lynwood.lv426-lock *enabled'; then
  omarchy plugin enable omarchy.lock >/dev/null 2>&1
fi
for id in lynwood.lv426-lock lynwood.lv426-lurk lynwood.motion-tracker; do
  omarchy plugin disable "$id" >/dev/null 2>&1
  rm -rf "$omarchy/plugins/$id"
done

rm -f "$omarchy/hooks/theme-set.d/lv-426-"{theme,font,extras}.sh \
  "$omarchy/hooks/post-boot.d/lv-426-theme.sh" \
  "$omarchy/hooks/battery-low.d/lv-426-self-destruct.sh"

sed -i '/# LV-426 terminal welcome (theme-gated)/d; /lv-426\/terminal\/startup.bash/d' "$HOME/.bashrc"

echo "Plugins, hooks and the terminal welcome are removed."
echo "The theme folder stays at $omarchy/themes/lv-426 (with any art you added)."
echo "Delete it with: rm -rf $omarchy/themes/lv-426"
