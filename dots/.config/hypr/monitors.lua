-- Per-host monitor layout: loads monitors/<hostname>.lua if it exists.
-- Add a layout for a new machine by creating monitors/$(hostnamectl hostname).lua
local f = io.open("/etc/hostname", "r")
local host = f and (f:read("*l") or ""):match("^%s*(.-)%s*$") or ""
if f then f:close() end

if host ~= "" and is_file_exists(HOME .. "/.config/hypr/monitors/" .. host .. ".lua") then
    require("monitors." .. host)
end
