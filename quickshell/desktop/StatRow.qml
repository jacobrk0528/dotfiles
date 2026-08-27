import QtQuick
import QtQuick.Layouts
import ".."

// One labelled meter in the desktop stats widget.
RowLayout {
    id: root

    property string label: ""
    property real value: 0        // 0..100
    property string detail: ""
    property color barColor: Theme.accent

    spacing: Theme.spacingM

    Text {
        Layout.preferredWidth: 38
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: Theme.textDim
        text: root.label
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 4
        radius: 2
        color: Theme.alpha(Theme.textPrimary, 0.12)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value / 100))
            height: parent.height
            radius: parent.radius
            color: root.barColor

            Behavior on width {
                NumberAnimation {
                    duration: Theme.durSlow
                    easing.type: Theme.easing
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durSlow
                }
            }
        }
    }

    Text {
        Layout.preferredWidth: 96
        horizontalAlignment: Text.AlignRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: Theme.textSecondary
        text: root.detail
    }
}
