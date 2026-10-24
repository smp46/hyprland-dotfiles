require("hyprland.lib")
require("hyprland.variables")

local qsIpcCall = "qs -c $qsConfig ipc call"
local qsIsAlive = qsIpcCall .. " TEST_ALIVE"

-- Edit keybinds shortcut
hl.bind(
	"CTRL + SUPER + ALT + Slash",
	hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"),
	{ description = "Edit user keybinds" }
)

-- Unbind default search triggers on Super tap so Super+Space is used instead
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER + SUPER_R")
hl.bind(
	"SUPER + SPACE",
	hl.dsp.global("quickshell:searchToggleRelease"),
	{ non_consuming = true, description = "Shell: Toggle search" }
)
hl.bind(
	"SUPER + SPACE",
	hl.dsp.exec_cmd(qsIsAlive .. " || pkill fuzzel || fuzzel"),
	{ description = "Shell: Launcher (fallback)" }
)

-- Window close: Super+Shift+Q instead of Super+Q
hl.unbind("SUPER + Q")
hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close(), { description = "Window: Close" })

-- Move window to workspace 1-10 with Super+Shift+Number
for i = 1, 10 do
	local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
	hl.bind("SUPER + SHIFT + " .. (i % 10), function()
		hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i) }))
	end, { description = "Window: Move to workspace " .. i })
	hl.bind("SUPER + SHIFT + code:" .. numberkey[i], function()
		hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i) }))
	end)
end

-- Custom application shortcuts
hl.bind("SUPER + SHIFT + RETURN", hl.dsp.exec_cmd("firefox -P personal"), { description = "App: Browser (Personal)" })

-- Unbind unused default app shortcuts as in pre-update config
hl.unbind("SUPER + W")
hl.unbind("SUPER + C")
hl.unbind("SUPER + T")
hl.unbind("CTRL + ALT + T")

-- Lock immediately when laptop lid is closed
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("loginctl lock-session"), { locked = true, description = "Session: Lock on lid close" })

