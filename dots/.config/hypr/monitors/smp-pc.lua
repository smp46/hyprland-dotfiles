-- smp-pc (desktop)
-- Keep monitor rules here, not in HyprMod's hyprland-gui.lua (that file is shared
-- by all hosts and loads after this one, so it would override every machine).
hl.monitor({
    output   = "DP-1",        -- ASUS VP28U 4K
    mode     = "3840x2160@60.00",
    position = "512x240",
    scale    = 1.07,
    cm       = "srgb",
})

hl.monitor({
    output   = "DP-3",        -- Samsung Odyssey G65B (primary)
    mode     = "2560x1440@239.97",
    position = "-2048x960",   -- right edge meets DP-1's left edge (x=512)
    scale    = 1.0,
    cm       = "srgb",
})
