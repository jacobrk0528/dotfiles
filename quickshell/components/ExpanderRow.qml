import QtQuick
import QtQuick.Layouts
import ".."

// Header row that toggles a section open, used by the control center.
MouseArea {
    id: root

    property string glyph: ""
    property string label: ""
    property string value: ""
    property color glyphColor: Theme.textPrimary
    property bool expanded: false
    property bool expandable: true

    Layout.fillWidth: true
    implicitHeight: 30
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -Theme.spacingS
        anchors.rightMargin: -Theme.spacingS
        radius: 6
        color: root.containsMouse ? Theme.hoverBg : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.durFast
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacingM

        Text {
            Layout.preferredWidth: 16
            font.family: Theme.fontFamily
            font.pixelSize: 15
            color: root.glyphColor
            text: root.glyph
        }

        Text {
            Layout.fillWidth: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textSecondary
            elide: Text.ElideRight
            text: root.label
        }

        Text {
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            color: Theme.textDim
            elide: Text.ElideRight
            text: root.value
        }

        Text {
            visible: root.expandable
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textDim
            text: root.expanded ? "󰅃" : "󰅀"
        }
    }
}
