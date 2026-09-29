import Quickshell
import QtQuick
import ".."

// Name label that floats above a dock tile.
PopupWindow {
    id: root

    required property Item target
    property string text

    visible: false
    anchor.item: root.target
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.margins.top: -8

    implicitWidth: label.implicitWidth + 24
    implicitHeight: label.implicitHeight + 14
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Theme.tooltipBg
        border.color: Theme.tooltipBorder
        border.width: 1
        radius: 8

        Text {
            id: label
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tooltipFontSize
            color: Theme.textPrimary
            text: root.text
        }
    }
}
