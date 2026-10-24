#!/usr/bin/env python3
"""KDE Connect helper for Quickshell KdeConnect service.

Communicates with KDE Connect via DBus (busctl / qdbus-qt6) or kdeconnect-cli.
Outputs structured JSON for QML consumption.
"""

import json
import os
import re
import shutil
import subprocess
import sys

SERVICES = ["org.kde.kdeconnect", "org.kde.kdeconnect.daemon"]
DAEMON_PATH = "/modules/kdeconnect"
DEVICES_PATH = DAEMON_PATH + "/devices"
DEVICE_IFACE = "org.kde.kdeconnect.device"
ID_PATTERN = re.compile(r"^[A-Za-z0-9_\-]+$")

LOG_FILE = "/tmp/kdeconnect.log"


def log(msg):
    if os.environ.get("KDECONNECT_DEBUG"):
        try:
            with open(LOG_FILE, "a") as f:
                f.write(f"{msg}\n")
        except Exception:
            pass


def find_active_service():
    for s in SERVICES:
        try:
            res = subprocess.run(
                ["busctl", "--user", "--json=short", "call", s, DAEMON_PATH, "org.freedesktop.DBus.Peer", "Ping"],
                capture_output=True, text=True, timeout=2,
            )
            if res.returncode == 0:
                return s
        except Exception:
            pass
    return SERVICES[0]


def get_property(service, path, iface, prop):
    # 1. Try busctl get-property
    try:
        cmd = ["busctl", "--user", "--json=short", "get-property", service, path, iface, prop]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout.strip())
            if "data" in data:
                return data["data"]
    except Exception as e:
        log(f"busctl get-property failed for {prop}: {e}")

    # 2. Try qdbus-qt6
    try:
        cmd = ["qdbus-qt6", service, path, f"{iface}.{prop}"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        if res.returncode == 0:
            val = res.stdout.strip()
            if val.lower() == "true":
                return True
            if val.lower() == "false":
                return False
            try:
                return int(val)
            except ValueError:
                return val
    except Exception as e:
        log(f"qdbus-qt6 failed for {prop}: {e}")

    return None


def get_device_ids(service):
    # 1. Try DBus daemon devices call
    try:
        cmd = ["busctl", "--user", "--json=short", "call", service, DAEMON_PATH, "org.kde.kdeconnect.daemon", "devices", "bb", "false", "false"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout.strip())
            raw_ids = data.get("data", [[]])[0]
            ids = [i for i in raw_ids if ID_PATTERN.match(str(i))]
            if ids:
                return ids
    except Exception as e:
        log(f"DBus devices call failed: {e}")

    # 2. Try kdeconnect-cli --list-devices
    if shutil.which("kdeconnect-cli"):
        try:
            res = subprocess.run(["kdeconnect-cli", "-l", "--id-only"], capture_output=True, text=True, timeout=3)
            if res.returncode == 0:
                ids = [line.strip() for line in res.stdout.splitlines() if line.strip() and ID_PATTERN.match(line.strip())]
                if ids:
                    return ids
        except Exception as e:
            log(f"kdeconnect-cli -l failed: {e}")

    return []


def get_device_battery(service, device_id):
    path = f"{DEVICES_PATH}/{device_id}/battery"
    iface = f"{DEVICE_IFACE}.battery"

    charge = get_property(service, path, iface, "charge")
    is_charging = get_property(service, path, iface, "isCharging")

    log(f"Device {device_id} raw battery: charge={charge}, isCharging={is_charging}")

    if charge is not None and isinstance(charge, (int, float)) and charge >= 0:
        return {
            "hasBattery": True,
            "charge": int(charge),
            "isCharging": bool(is_charging),
        }

    return {"hasBattery": False, "charge": -1, "isCharging": False}


def cmd_list():
    service = find_active_service()
    log(f"Listing devices using service: {service}")

    device_ids = get_device_ids(service)
    log(f"Found device ids: {device_ids}")

    devices = []
    for dev_id in device_ids:
        path = f"{DEVICES_PATH}/{dev_id}"
        name = get_property(service, path, DEVICE_IFACE, "name") or dev_id
        is_reachable = get_property(service, path, DEVICE_IFACE, "isReachable")
        dev_type = get_property(service, path, DEVICE_IFACE, "type") or "phone"

        reachable_bool = bool(is_reachable) if is_reachable is not None else True
        batt = get_device_battery(service, dev_id) if reachable_bool else {"hasBattery": False, "charge": -1, "isCharging": False}

        devices.append({
            "id": dev_id,
            "name": str(name),
            "type": str(dev_type),
            "reachable": reachable_bool,
            "hasBattery": batt["hasBattery"],
            "charge": batt["charge"],
            "charging": batt["isCharging"],
            "canPing": True,
            "canClipboard": True,
            "canShare": True,
            "canRing": True,
        })

    result = json.dumps({"devices": devices})
    log(f"Returning: {result}")
    print(result)


def run_action(action, device_id, argument=None):
    if not ID_PATTERN.match(device_id):
        print(json.dumps({"error": "invalid device id"}))
        return

    cli_map = {
        "ping": ["kdeconnect-cli", "--ping", "-d", device_id],
        "ring": ["kdeconnect-cli", "--ring", "-d", device_id],
        "share-text": ["kdeconnect-cli", "--share-text", str(argument), "-d", device_id],
        "share-url": ["kdeconnect-cli", "--share", str(argument), "-d", device_id],
    }

    if action in cli_map and shutil.which("kdeconnect-cli"):
        try:
            subprocess.run(cli_map[action], check=True, timeout=5)
            print(json.dumps({"status": "ok"}))
            return
        except Exception as e:
            log(f"Action {action} failed via cli: {e}")

    if action == "clipboard":
        try:
            paste_res = subprocess.run(["wl-paste", "--no-newline"], capture_output=True, text=True, timeout=3)
            clip_text = paste_res.stdout
            if clip_text and shutil.which("kdeconnect-cli"):
                subprocess.run(["kdeconnect-cli", "--share-text", clip_text, "-d", device_id], check=True, timeout=5)
                print(json.dumps({"status": "ok"}))
                return
        except Exception as e:
            log(f"Clipboard action failed: {e}")

    if action == "share-file" and argument:
        if shutil.which("kdeconnect-cli"):
            try:
                subprocess.run(["kdeconnect-cli", "--share", str(argument), "-d", device_id], check=True, timeout=10)
                print(json.dumps({"status": "ok"}))
                return
            except Exception as e:
                log(f"Share-file failed: {e}")

    print(json.dumps({"error": f"action {action} failed"}))


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "no command specified"}))
        return

    cmd = sys.argv[1]
    if cmd == "list":
        cmd_list()
    elif cmd in ("ping", "ring", "clipboard") and len(sys.argv) >= 3:
        run_action(cmd, sys.argv[2])
    elif cmd in ("share-text", "share-url", "share-file") and len(sys.argv) >= 4:
        run_action(cmd, sys.argv[2], sys.argv[3])
    else:
        print(json.dumps({"error": f"unknown command {cmd}"}))


if __name__ == "__main__":
    main()
