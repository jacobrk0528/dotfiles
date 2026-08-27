import QtQuick
import ".."

// Small square glyph button used in cards, panels and headers.
MouseArea {
    id: root

    property string glyph: ""
    property int size: 24
    property int glyphSize: Theme.fontSize
    property color glyphColor: Theme.textSecondary
    property color hoverColor: Theme.textPrimary

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.pressed ? Theme.pressedBg : root.containsMouse ? Theme.hoverBg : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.durFast
            }
        }
    }

    Text {
        anchors.centerIn: parent
        font.family: Theme.fontFamily
        font.pixelSize: root.glyphSize
        color: root.containsMouse ? root.hoverColor : root.glyphColor
        text: root.glyph

        Behavior on color {
            ColorAnimation {
                duration: Theme.durFast
            }
        }
    }
}
