pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

PopupWindow {
    id: root

    required property Item anchorItem

    signal popupOpened()
    signal popupClosed()

    color: "transparent"
    property real popupPadding: Appearance.sizes.elevationMargin

    anchor {
        window: root.anchorItem?.QsWindow?.window
        item: root.anchorItem
        gravity: Config.options.bar.vertical
            ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
            : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
        edges: Config.options.bar.vertical
            ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
            : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: root.visible
        windows: [root]
        onCleared: root.close()
    }

    function open() {
        root.visible = true;
        KdeConnect.refresh();
        root.popupOpened();
    }

    function close() {
        root.visible = false;
        root.popupClosed();
    }

    implicitWidth: popupBackground.implicitWidth + root.popupPadding * 2
    implicitHeight: popupBackground.implicitHeight + root.popupPadding * 2

    StyledRectangularShadow {
        target: popupBackground
        opacity: popupBackground.opacity
    }

    Rectangle {
        id: popupBackground
        readonly property real contentPadding: 14

        anchors {
            fill: parent
            margins: root.popupPadding
        }

        implicitWidth: 320
        implicitHeight: contentColumn.implicitHeight + contentPadding * 2

        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.windowRounding
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: popupBackground.contentPadding
            }
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: {
                        const type = KdeConnect.device?.type ?? "phone";
                        if (type === "tablet") return "tablet_android";
                        if (type === "desktop" || type === "laptop") return "computer";
                        return "smartphone";
                    }
                    iconSize: Appearance.font.pixelSize.huge
                    color: KdeConnect.device?.reachable ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: KdeConnect.device?.name ?? Translation.tr("KDE Connect")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (!KdeConnect.daemonAvailable) return Translation.tr("Daemon unavailable");
                            if (!KdeConnect.hasDevices) return Translation.tr("No paired devices");
                            return KdeConnect.device?.reachable ? Translation.tr("Connected") : Translation.tr("Disconnected");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: KdeConnect.device?.reachable ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    downAction: () => root.close()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Multiple Devices Selector
            RowLayout {
                Layout.fillWidth: true
                visible: KdeConnect.devices.length > 1
                spacing: 6

                Repeater {
                    model: KdeConnect.devices
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.small
                        toggled: KdeConnect.device?.id === modelData.id
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        downAction: () => KdeConnect.selectDevice(modelData.id)

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: modelData.reachable ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Battery Section
            ColumnLayout {
                Layout.fillWidth: true
                visible: KdeConnect.device?.hasBattery && KdeConnect.device?.reachable
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: KdeConnect.device?.charging ? "battery_charging_full" : "battery_android_full"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        text: Translation.tr("Battery")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: `${KdeConnect.device?.charge ?? 0}%`
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    valueBarHeight: 6
                    value: (KdeConnect.device?.charge ?? 0) / 100
                    highlightColor: Appearance.colors.colPrimary
                    trackColor: Appearance.colors.colLayer2
                }
            }

            // Status Notice Banner
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: noticeLayout.implicitHeight + 10
                radius: Appearance.rounding.small
                color: KdeConnect.noticeIsError ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                visible: KdeConnect.notice !== ""

                Behavior on visible {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: noticeLayout
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 6

                    MaterialSymbol {
                        text: KdeConnect.noticeIsError ? "error" : "check_circle"
                        iconSize: Appearance.font.pixelSize.small
                        color: KdeConnect.noticeIsError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: KdeConnect.notice
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: KdeConnect.noticeIsError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                    }
                }
            }

            // Actions Grid
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                visible: KdeConnect.device?.reachable ?? false

                ActionButton {
                    actionIcon: "ring_volume"
                    label: Translation.tr("Find Phone")
                    onClicked: {
                        if (KdeConnect.device) KdeConnect.ring(KdeConnect.device.id);
                    }
                }

                ActionButton {
                    actionIcon: "content_copy"
                    label: Translation.tr("Send Clipboard")
                    onClicked: {
                        if (KdeConnect.device) KdeConnect.sendClipboard(KdeConnect.device.id);
                    }
                }

                ActionButton {
                    actionIcon: "folder_open"
                    label: Translation.tr("Send File")
                    onClicked: {
                        if (KdeConnect.device) KdeConnect.pickAndShare(KdeConnect.device.id);
                    }
                }

                ActionButton {
                    actionIcon: "network_ping"
                    label: Translation.tr("Ping")
                    onClicked: {
                        if (KdeConnect.device) KdeConnect.ping(KdeConnect.device.id);
                    }
                }
            }

            // Disconnected Help Text
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: helpLayout.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                visible: !KdeConnect.device?.reachable

                ColumnLayout {
                    id: helpLayout
                    anchors {
                        fill: parent
                        margins: 8
                    }
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: !KdeConnect.hasDevices
                            ? Translation.tr("No devices paired yet. Open KDE Connect to pair your phone.")
                            : Translation.tr("Device is unreachable. Make sure both devices are on the same network.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Footer
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: {
                    KdeConnect.openApp();
                    root.close();
                }

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "settings"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: Translation.tr("Open KDE Connect")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }

    component ActionButton: RippleButton {
        id: actBtn
        property string actionIcon: ""
        property string label: ""

        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 8

            MaterialSymbol {
                text: actBtn.actionIcon
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: actBtn.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
        }
    }
}
