return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = "#050806",
        dark_bg = "#030504",
        darker_bg = "#010202",
        lighter_bg = "#0E1612",

        fg = "#B8C4BC",
        dark_fg = "#6E7C74",
        light_fg = "#9AA89F",
        bright_fg = "#E2EEE6",
        muted = "#4F5E55",

        red = "#D9534A",
        yellow = "#E8A33D",
        orange = "#D9782B",
        green = "#6FE39A",
        cyan = "#5FC9B8",
        blue = "#6B9FB8",
        magenta = "#A58FB0",
        brown = "#8A7356",

        bright_red = "#F07A6E",
        bright_yellow = "#FFC266",
        bright_green = "#A6FFC4",
        bright_cyan = "#8FE8D9",
        bright_blue = "#9CC4D8",
        bright_magenta = "#C4B0D0",

        accent = "#6FE39A",
        cursor = "#6FE39A",
        foreground = "#B8C4BC",
        background = "#050806",
        selection = "#12301F",
        selection_foreground = "#E2EEE6",
        selection_background = "#1A4A2E",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
