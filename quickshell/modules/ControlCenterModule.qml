import QtQuick
import ".."
import "../components"
import "../services"

// macOS-style two-switch glyph; opens the control center (same as SUPER+C).
BarModule {
    id: root

    readonly property color glyphColor: Panels.open === "control" ? Theme.accent : Theme.textSecondary

    visible: true
    implicitWidth: glyph.width + horizontalPadding * 2
    tooltipText: "Control center"

    onLeftClicked: Panels.toggle("control")

    Column {
        id: glyph
        anchors.centerIn: parent
        spacing: 2

        // Off switch: outlined track, knob on the left
        Rectangle {
            width: 15
            height: 7
            radius: height / 2
            color: "transparent"
            border.color: root.glyphColor
            border.width: 1

            Rectangle {
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 3
                radius: 1.5
                color: root.glyphColor
            }
        }

        // On switch: filled track, knob on the right
        Rectangle {
            width: 15
            height: 7
            radius: height / 2
            color: root.glyphColor

            Rectangle {
                x: parent.width - width - 2
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 3
                radius: 1.5
                color: Theme.base
            }
        }
    }
}
