-- LV-426 / MU-TH-UR 6000
-- Hand-tuned: Omarchy's generated borders plus a phosphor glow that bleeds
-- from the focused window like light from a CRT. Unfocused windows get none.
local active_border_color = { colors = { "rgba(6FE39Aee)", "rgba(1E4A30cc)" }, angle = 45 }
local inactive_border_color = "rgba(1A2620aa)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    shadow = {
      enabled = true,
      range = 22,
      render_power = 2,
      color = "rgba(6FE39A40)",
      color_inactive = "rgba(00000000)",
    },
  },
})

-- Motion: windows pounce in with a short overshoot (facehugger), slip out
-- fast, and workspaces slide vertically like Nostromo bulkhead doors.
hl.curve("pounce", { type = "bezier", points = { { 0.22, 1.45 }, { 0.36, 1 } } })
hl.curve("bulkhead", { type = "bezier", points = { { 0.7, 0 }, { 0.2, 1 } } })
hl.curve("retreat", { type = "bezier", points = { { 0.55, 0 }, { 1, 0.45 } } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.2, bezier = "pounce", style = "popin 55%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.6, bezier = "retreat", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.5, bezier = "pounce" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.2, bezier = "bulkhead", style = "slidevert" })
hl.animation({ leaf = "border", enabled = true, speed = 2.5, bezier = "bulkhead" })

-- LV-426 extras: SUPER+ALT+C toggles CRT mode, SUPER+ALT+M opens MOTHER.
if o and o.bind then
  local lv = os.getenv("HOME") .. "/.config/omarchy/themes/lv-426/bin/"
  o.bind("SUPER + ALT + C", "LV-426: CRT mode", lv .. "lv426-crt")
  o.bind("SUPER + ALT + M", "LV-426: MOTHER console", { tui = lv .. "mother" })
end
