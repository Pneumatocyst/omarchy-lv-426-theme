# Local interactive terminals only; run once per TTY, not in nested shells.
if [[ $- == *i* && -t 0 && -t 1 && ${TERM:-dumb} != dumb && -z ${SSH_CONNECTION:-} && -z ${BASH_EXECUTION_STRING:-} ]]; then
  if [[ -r "$HOME/.local/state/omarchy/current/theme.name" && $(< "$HOME/.local/state/omarchy/current/theme.name") == lv-426 ]]; then
    export STARSHIP_CONFIG="$HOME/.config/omarchy/themes/lv-426/starship.toml"
    mother() { "$HOME/.config/omarchy/themes/lv-426/bin/mother" "$@"; }
    xeno() { python3 "$HOME/.config/omarchy/themes/lv-426/terminal/xenomorph.py" "$@"; }
    _lv426_tty=$(tty 2>/dev/null)
    if [[ ${LV426_INTRO_TTY:-} != "$_lv426_tty" ]]; then
      export LV426_INTRO_TTY="$_lv426_tty"
      python3 "$HOME/.config/omarchy/themes/lv-426/terminal/xenomorph.py" --intro
    fi
    unset _lv426_tty
  fi
fi
