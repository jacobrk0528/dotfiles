import QtQuick
import ".."

// Pill-shaped labelled button, used for notification actions and panel controls.
MouseArea {
    id: root

    property string label: ""
    property bool accented: false

    implicitWidth: text.implicitWidth + Theme.spacingL
    implicitHeight: 26
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.pressed ? Theme.pressedBg : root.containsMouse ? Theme.activeBg : Theme.hoverBg
        border.width: 1
        border.color: root.accented ? Theme.alpha(Theme.accent, 0.4) : Theme.pillBorder

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
        color: root.accented ? Theme.accent : Theme.textSecondary
        text: root.label
    }
}
