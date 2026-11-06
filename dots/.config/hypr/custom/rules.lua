-- Force terminal to always spawn tiled
hl.window_rule({ match = { class = "^(kitty|foot|Alacritty)$" }, tile = true })
-- Ignore the terminal's own maximize/fullscreen requests (SUPER+D / SUPER+F still work)
hl.window_rule({ match = { class = "^(kitty|foot|Alacritty)$" }, suppress_event = "maximize fullscreen fullscreenoutput" })

-- Phone mirroring (scrcpy): normal floating window, hidden/shown by custom/scripts/phone-mirror.sh
hl.window_rule({ match = { class = "^(scrcpy)$" }, float = true })
-- Don't let scrcpy block Hyprland shortcuts while it's focused
hl.window_rule({ match = { class = "^(scrcpy)$" }, no_shortcuts_inhibit = true })
-- Half the monitor height, keeping the phone's 1080x2424 aspect ratio
hl.window_rule({ match = { class = "^(scrcpy)$" }, size = {"(monitor_h*0.2228)", "(monitor_h*0.5)"} })
hl.window_rule({ match = { class = "^(scrcpy)$" }, center = true })
-- Match the phone's display corners (115px radius on a 1080px-wide screen, about 10.6% of the width)
hl.window_rule({ match = { class = "^(scrcpy)$" }, rounding = 34 })
hl.window_rule({ match = { class = "^(scrcpy)$" }, rounding_power = 2 })
