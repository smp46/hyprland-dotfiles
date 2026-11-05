hl.on("hyprland.start", function ()
    -- Activate graphical-session.target so systemd user services that require it
    -- (xdg-desktop-portal, KDE Connect's portal, etc.) can start without uwsm.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE DISPLAY && systemctl --user start hyprland-session.target")
end)
