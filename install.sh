#!/usr/bin/env bash
# LV-426 full install: theme files, shell plugins, hooks and the terminal
# welcome. Run it from a clone that is NOT inside ~/.config/omarchy/themes:
#
#   git clone https://github.com/Pneumatocyst/omarchy-lv-426-theme ~/.local/share/lv-426
#   ~/.local/share/lv-426/install.sh
#
# Update later with: git -C ~/.local/share/lv-426 pull && ~/.local/share/lv-426/install.sh
set -euo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
omarchy="$HOME/.config/omarchy"
dest="$omarchy/themes/lv-426"
green=$'\e[32m' amber=$'\e[33m' reset=$'\e[0m'

say() { printf '%s▌MU/TH/UR%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s▌WARNING%s  %s\n' "$amber" "$reset" "$*"; }
ask() { # question -> 0 for yes
  if command -v gum >/dev/null; then gum confirm "$1"; else
    read -rp "$1 [y/N] " reply; [[ $reply == [yY]* ]]; fi
}

if [[ $(cd "$dest" 2>/dev/null && pwd -P) == "$src" ]]; then
  warn "This clone is the theme folder itself. Clone it somewhere else"
  warn "(e.g. ~/.local/share/lv-426) and run install.sh from there."
  exit 1
fi

# Omarchy treats a theme folder holding .git as untrusted and drops its .lua
# files (the glow, motion and CRT/MOTHER keybinds), so install a plain copy.
say "Copying theme to $dest"
mkdir -p "$dest"
rm -rf "$dest/.git"
# No --delete: your own backgrounds/ image and animation/photo.png +
# creatures.mp4 survive updates.
rsync -a --exclude .git --exclude extras --exclude docs \
  --exclude install.sh --exclude uninstall.sh "$src/" "$dest/"

say "Installing shell plugins"
mkdir -p "$omarchy/plugins"
cp -r "$src/extras/plugins/"* "$omarchy/plugins/"

say "Installing hooks"
for dir in "$src/extras/hooks/"*/; do
  name=$(basename "$dir")
  mkdir -p "$omarchy/hooks/$name"
  install -m 755 "$dir"*.sh "$omarchy/hooks/$name/"
done

if ! grep -q 'lv-426/terminal/startup.bash' "$HOME/.bashrc" 2>/dev/null; then
  say "Adding the terminal welcome to ~/.bashrc"
  cat >> "$HOME/.bashrc" <<'EOF'

# LV-426 terminal welcome (theme-gated)
[[ -r "$HOME/.config/omarchy/themes/lv-426/terminal/startup.bash" ]] && source "$HOME/.config/omarchy/themes/lv-426/terminal/startup.bash"
EOF
fi

if ! fc-list | grep -Fqi '3270 Nerd Font'; then
  if command -v pacman >/dev/null && ask "Install the IBM 3270 font (ttf-3270-nerd, needs sudo)?"; then
    sudo pacman -S --needed ttf-3270-nerd
  else
    warn "Without ttf-3270-nerd LV-426 keeps your current font."
  fi
fi

missing=()
for cmd in ffmpeg fastfetch starship jq pw-play dbus-monitor python3; do
  command -v "$cmd" >/dev/null || missing+=("$cmd")
done
python3 -c 'import gi, cairo; gi.require_version("Gtk4LayerShell", "1.0")' 2>/dev/null ||
  missing+=("python-gobject python-cairo gtk4-layer-shell")
((${#missing[@]})) && warn "Missing (some features stay off): ${missing[*]}"

say "Enabling plugins"
omarchy plugin enable lynwood.motion-tracker --section right >/dev/null 2>&1 ||
  warn "Enable the M314 tracker by hand: omarchy plugin enable lynwood.motion-tracker"
omarchy plugin enable lynwood.lv426-lurk >/dev/null 2>&1 || true
if ask "Use the MU-TH-UR lock screen? (replaces the Omarchy lock screen; uninstall.sh restores it)"; then
  omarchy plugin enable lynwood.lv426-lock >/dev/null 2>&1 &&
    omarchy plugin disable omarchy.lock >/dev/null 2>&1 || true
fi

if ! compgen -G "$dest/backgrounds/*.*" >/dev/null; then
  warn "No wallpaper yet: put an image in $dest/backgrounds/ (see README)."
fi

say "Selecting LV-426"
omarchy theme set lv-426
say "INTERFACE 2037 READY FOR INQUIRY. Try SUPER+ALT+C and SUPER+ALT+M."
