import QtQuick

// idx1 is the "leading" indicator position, idx2 is the "following" one
// The former animates faster than the latter, see the NumberAnimations below
QtObject {
    id: root
    required property int index

    property real idx1: index
    property real idx2: index
    property int idx1Duration: 80
    property int idx2Duration: 180
    property int easingType: Easing.OutCubic

    Behavior on idx1 {
        NumberAnimation {
            duration: root.idx1Duration
            easing.type: root.easingType
        }
    }
    Behavior on idx2 {
        NumberAnimation {
            duration: root.idx2Duration
            easing.type: root.easingType
        }
    }
}
