import Quickshell
import QtQuick
import ".."
import "../components"
import "../services"

// A window parked on special:minimized. Click brings it back onto the
// current workspace; middle click closes it.
MouseArea {
    id: root

    required property var modelData
    readonly property var entry: DockApps.entryFor(root.modelData["class"])

    implicitWidth: Theme.dockIconSize + 14
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    onClicked: event => {
        tip.visible = false;
        if (event.button === Qt.MiddleButton)
            DockApps.close(root.modelData);
        else
            DockApps.restore(root.modelData);
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.radius
        color: root.pressed ? Theme.pressedBg : root.containsMouse ? Theme.hoverBg : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durFast }
        }
    }

    AppIcon {
        id: icon
        anchors.centerIn: parent
        size: Theme.dockIconSize - 8
        source: DockApps.iconFor(root.entry, root.modelData["class"])
        name: DockApps.nameFor(root.entry, root.modelData["class"])
        opacity: root.containsMouse ? 1 : 0.55
        scale: root.containsMouse ? 1.08 : 1

        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easing }
        }
    }

    // Minimize glyph in the corner, like the macOS Dock's app badge
    Text {
        anchors.right: icon.right
        anchors.bottom: icon.bottom
        anchors.rightMargin: -4
        anchors.bottomMargin: -4
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Theme.textSecondary
        text: "󰖰"
    }

    onContainsMouseChanged: {
        if (containsMouse)
            tipDelay.restart();
        else {
            tipDelay.stop();
            tip.visible = false;
        }
    }

    Timer {
        id: tipDelay
        interval: 350
        onTriggered: tip.visible = root.containsMouse
    }

    DockTooltip {
        id: tip
        target: root
        text: {
            const t = String(root.modelData.title ?? "");
            return t.length > 60 ? t.slice(0, 59) + "…" : t;
        }
    }
}
