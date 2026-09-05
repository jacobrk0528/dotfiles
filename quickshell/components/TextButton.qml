import QtQuick
import ".."

// Pill-shaped labelled button, used for notification actions and panel controls.
MouseArea {
    id: root

    property string label: ""
    property bool accented: false
    property color accentColor: Theme.accent
    // Keyboard-navigation cursor, independent of accented (which reflects
    // on/off state, not selection).
    property bool current: false

    implicitWidth: text.implicitWidth + Theme.spacingL
    implicitHeight: 26
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.pressed ? Theme.pressedBg : root.containsMouse ? Theme.activeBg : Theme.hoverBg
        border.width: root.current ? 2 : 1
        border.color: root.current ? Theme.textPrimary : root.accented ? Theme.alpha(root.accentColor, 0.4) : Theme.pillBorder

        Behavior on color {
            ColorAnimation {
                duration: Theme.durFast
            }
        }
    }

    Text {
        id: text
        anchors.centerIn: parent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: root.accented ? root.accentColor : Theme.textSecondary
        text: root.label
    }
}
