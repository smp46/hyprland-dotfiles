#!/usr/bin/env bash
# Toggle Android screen mirroring (scrcpy) as a normal floating window.
#   - window on the current workspace -> hide it (stash in special:phone, never shown)
#   - window hidden / elsewhere       -> bring it to the current workspace and focus it
#   - not running                     -> connect via adb (mDNS discovery) and launch scrcpy
# Extra args are passed to scrcpy, e.g. --start-app=org.example.app
# No device identifiers are stored here; everything is discovered at runtime.

if pgrep -x scrcpy >/dev/null; then
    read -r addr ws < <(hyprctl clients -j | jq -r '.[] | select(.class == "scrcpy") | "\(.address) \(.workspace.id)"' | head -n1)
    [ -z "$addr" ] && exit 0   # still starting up, no window yet
    cur=$(hyprctl activeworkspace -j | jq -r '.id')
    if [ "$ws" = "$cur" ]; then
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:phone\", follow = false, window = \"address:$addr\" })" >/dev/null
    else
        hyprctl dispatch "hl.dsp.window.move({ workspace = $cur, follow = true, window = \"address:$addr\" })" >/dev/null
        sleep 0.05
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
    fi
    exit 0
fi

has_device() { adb devices | grep -q $'\tdevice$'; }

if ! has_device; then
    endpoint=$(timeout 5 adb mdns services 2>/dev/null | awk '/_adb-tls-connect/ {print $NF; exit}')
    [ -n "$endpoint" ] && timeout 5 adb connect "$endpoint" >/dev/null 2>&1
fi

if ! has_device; then
    notify-send -a "Phone" -i smartphone "Phone" "Not reachable — is Wireless debugging on?"
    exit 1
fi

# --screen-off-timeout keeps the phone from locking over Wi-Fi (--stay-awake only works when plugged in);
# the phone's own timeout is restored when scrcpy exits.
setsid -f scrcpy --window-title="Phone" --turn-screen-off --screen-off-timeout=1800 \
    --max-fps=60 --video-codec=h265 \
    --keyboard=uhid --power-off-on-close "$@" >/dev/null 2>&1
