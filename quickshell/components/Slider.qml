import QtQuick
import ".."

// Horizontal 0..1 slider. Emits `moved` on drag/click; the caller owns the value.
Item {
    id: root

    property real value: 0
    property color fillColor: Theme.accent
    // Optional live level (0..1) drawn behind the fill, e.g. a peak meter.
    property real level: 0
    property bool showLevel: false

    signal moved(real value)

    implicitHeight: 18

    function setFromX(x) {
        root.moved(Math.max(0, Math.min(1, x / root.width)));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: mouse.containsMouse || mouse.pressed ? 8 : 6
        radius: height / 2
        color: Theme.alpha(Theme.textPrimary, 0.1)

        Behavior on height {
            NumberAnimation {
                duration: Theme.durFast
            }
        }

        Rectangle {
            visible: root.showLevel
            width: parent.width * Math.min(1, root.level)
            height: parent.height
            radius: parent.radius
            color: Theme.alpha(root.fillColor, 0.25)
        }

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: parent.radius
            color: root.fillColor

            Behavior on width {
                enabled: !mouse.pressed
                NumberAnimation {
                    duration: Theme.durFast
                    easing.type: Theme.easing
                }
            }
        }
    }

    Rectangle {
        id: knob
        width: 12
        height: 12
        radius: 6
        anchors.verticalCenter: parent.verticalCenter
        x: track.width * Math.max(0, Math.min(1, root.value)) - width / 2
        color: root.fillColor
        opacity: mouse.containsMouse || mouse.pressed ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durFast
            }
        }

        Behavior on x {
            enabled: !mouse.pressed
            NumberAnimation {
                duration: Theme.durFast
                easing.type: Theme.easing
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onPressed: event => root.setFromX(event.x)
        onPositionChanged: event => {
            if (pressed)
                root.setFromX(event.x);
        }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
