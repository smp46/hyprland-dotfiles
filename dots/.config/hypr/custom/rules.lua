-- Force terminal to always spawn tiled
hl.window_rule({ match = { class = "^(kitty|foot|Alacritty)$" }, tile = true })
-- Ignore the terminal's own maximize/fullscreen requests (SUPER+D / SUPER+F still work)
hl.window_rule({ match = { class = "^(kitty|foot|Alacritty)$" }, suppress_event = "maximize fullscreen fullscreenoutput" })
