-- Force terminal to always spawn tiled
hl.window_rule({ match = { class = "^(kitty|foot|Alacritty)$" }, tile = true })
