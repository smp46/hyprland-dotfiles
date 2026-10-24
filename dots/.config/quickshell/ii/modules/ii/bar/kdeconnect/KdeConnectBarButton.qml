pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property color colBackground: "transparent"
    property bool popupOpen: popupLoader.active && popupLoader.item && popupLoader.item.visible

    readonly property bool isReachable: KdeConnect.device?.reachable ?? false
    readonly property bool hasBattery: isReachable && (KdeConnect.device?.hasBattery ?? false) && ((KdeConnect.device?.charge ?? -1) >= 0)
    readonly property real charge: Math.max(0, KdeConnect.device?.charge ?? 0)
    readonly property bool isCharging: isReachable && (KdeConnect.device?.charging ?? false)
    readonly property bool isLow: hasBattery && !isCharging && (charge <= 20)
    readonly property string deviceName: KdeConnect.device?.name ?? Translation.tr("Phone")

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    RippleButton {
        id: button
        anchors.fill: parent

        buttonRadius: Appearance.rounding.full
        colBackground: root.popupOpen
            ? Appearance.colors.colSecondaryContainer
            : (button.hovered ? Appearance.colors.colLayer1Hover : root.colBackground)
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        toggled: root.popupOpen

        property color colContent: {
            if (root.popupOpen) return Appearance.m3colors.m3onSecondaryContainer;
            if (!root.isReachable) return Appearance.colors.colSubtext;
            if (root.isLow) return Appearance.colors.colError;
            return Appearance.colors.colOnLayer0;
        }

        property color batteryFillColor: {
            if (root.popupOpen) return Appearance.m3colors.m3onSecondaryContainer;
            if (root.isCharging) return Appearance.colors.colPrimary;
            if (root.isLow) return Appearance.colors.colError;
            return Appearance.colors.colPrimary;
        }

        property color batteryTrackColor: ColorUtils.transparentize(batteryFillColor, 0.72)

        implicitHeight: Appearance.sizes.barHeight - 8
        implicitWidth: contentRow.implicitWidth + 14

        onClicked: {
            if (root.popupOpen) {
                popupLoader.item.close();
            } else {
                popupLoader.active = true;
                if (popupLoader.item) popupLoader.item.open();
            }
        }

        altAction: () => {
            KdeConnect.openApp();
        }

        contentItem: RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 5

            // Phone Icon
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: !root.isReachable ? "phonelink_off" : "smartphone"
                iconSize: Appearance.font.pixelSize.larger
                color: button.colContent
                opacity: root.isReachable ? 1.0 : 0.6

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            // Vertical Battery Bar
            Item {
                id: batteryBarContainer
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasBattery
                implicitWidth: 5
                implicitHeight: 16

                // Outer Track
                Rectangle {
                    id: batteryTrack
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: button.batteryTrackColor

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    // Inner Fill
                    Rectangle {
                        id: batteryFill
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: Math.max(parent.width, parent.height * Math.min(1.0, Math.max(0.05, root.charge / 100.0)))
                        radius: Appearance.rounding.full
                        color: button.batteryFillColor

                        Behavior on height {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }

            // Charging Bolt Icon
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.isCharging
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller
                color: button.batteryFillColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }

    PopupToolTip {
        id: tooltip
        text: {
            if (!KdeConnect.hasDevices) return Translation.tr("No phones paired\nClick to setup");
            if (!root.isReachable) return Translation.tr("%1 (Offline)\nClick to manage").arg(root.deviceName);
            let status = root.deviceName;
            if (root.hasBattery) {
                status += ` • ${Math.round(root.charge)}%`;
                if (root.isCharging) status += ` (${Translation.tr("Charging")})`;
            }
            return `${status}\n${Translation.tr("Click to manage • Right-click to open app")}`;
        }
        extraVisibleCondition: button.hovered && !root.popupOpen
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
    }

    Loader {
        id: popupLoader
        active: false

        sourceComponent: KdeConnectPopup {
            anchorItem: root
            onPopupOpened: root.popupOpen = true
            onPopupClosed: {
                root.popupOpen = false
                popupLoader.active = false
            }
        }

        onLoaded: {
            if (item) item.open();
        }
    }
}
