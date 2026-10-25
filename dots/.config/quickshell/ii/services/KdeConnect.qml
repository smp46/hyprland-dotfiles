pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    readonly property string script: FileUtils.trimFileProtocol(Directories.scriptPath + "/kdeconnect.py")

    property var devices: []
    property string selectedDeviceId: ""
    property bool daemonAvailable: true
    property string notice: ""
    property bool noticeIsError: false

    readonly property var device: {
        if (selectedDeviceId !== "") {
            for (let i = 0; i < devices.length; i++) {
                if (devices[i].id === selectedDeviceId) return devices[i];
            }
        }
        for (let j = 0; j < devices.length; j++) {
            if (devices[j].reachable) return devices[j];
        }
        return devices.length > 0 ? devices[0] : null;
    }

    readonly property bool anyReachable: devices.some(d => d.reachable)
    readonly property bool hasDevices: devices.length > 0

    function selectDevice(id) {
        selectedDeviceId = id;
    }

    function refresh() {
        if (!listProc.running) listProc.running = true;
    }

    Timer {
        id: pollTimer
        interval: 30000 // Popup refreshes on open; battery changes slowly
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["python3", root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let msg = JSON.parse(text.trim());
                    if (msg.devices !== undefined) {
                        root.devices = msg.devices;
                        root.daemonAvailable = true;
                        return;
                    }
                } catch (e) {}
                root.daemonAvailable = false;
                root.devices = [];
            }
        }
    }

    function showNotice(message, isError) {
        root.notice = message;
        root.noticeIsError = !!isError;
        noticeTimer.restart();
    }

    Timer {
        id: noticeTimer
        interval: 3000
        onTriggered: {
            root.notice = "";
            root.noticeIsError = false;
        }
    }

    Component {
        id: actionRunner
        Process {
            id: proc
            property string okMessage: ""
            property bool failed: false
            stdout: SplitParser {
                onRead: function(line) {
                    try {
                        let msg = JSON.parse(line);
                        if (msg.error) {
                            proc.failed = true;
                            root.showNotice(msg.error, true);
                        }
                    } catch (e) {}
                }
            }
            onExited: {
                if (!proc.failed && proc.okMessage !== "") {
                    root.showNotice(proc.okMessage, false);
                }
                destroy(100);
            }
        }
    }

    function run(args, okMessage) {
        actionRunner.createObject(root, {
            "command": ["python3", root.script].concat(args),
            "okMessage": okMessage,
            "running": true
        });
    }

    function ring(id) {
        run(["ring", id], Translation.tr("Ringing phone"));
    }

    function ping(id) {
        run(["ping", id], Translation.tr("Ping sent"));
    }

    function sendClipboard(id) {
        run(["clipboard", id], Translation.tr("Clipboard sent"));
    }

    function shareText(id, text) {
        let t = text.trim();
        if (t === "") return;
        let isUrl = /^https?:\/\/\S+$/.test(t);
        run([isUrl ? "share-url" : "share-text", id, t], isUrl ? Translation.tr("Link sent") : Translation.tr("Text sent"));
    }

    property string pickTarget: ""

    function pickAndShare(id) {
        if (pickProc.running) return;
        root.pickTarget = id;
        pickProc.running = true;
    }

    Process {
        id: pickProc
        command: ["sh", "-c", "if command -v kdialog >/dev/null; then kdialog --getopenfilename \"$HOME\"; else zenity --file-selection; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let path = text.trim();
                if (path !== "") {
                    root.run(["share-file", root.pickTarget, path], Translation.tr("File sent"));
                }
            }
        }
    }

    function openApp() {
        const win = HyprlandData?.windowList?.find(w => w.class === "org.kde.kdeconnect.app" || w.initialClass === "org.kde.kdeconnect.app");
        if (win && win.address) {
            Hyprland.dispatch(`hl.dsp.focus({window = "address:${win.address}"})`);
        } else {
            Quickshell.execDetached(["kdeconnect-app"]);
        }
    }
}
