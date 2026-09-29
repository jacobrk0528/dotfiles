import Quickshell
import QtQuick
import ".."
import "../components"
import "../services"

// One app in the dock. Left click launches / focuses / cycles its windows,
// middle click opens a new instance, right click opens the menu. Press and
// drag sideways to reorder; the order is saved to dock.json.
Item {
    id: root

    required property string key
    required property int index
    property ListView list
    property DockMenu menu

    readonly property var app: DockApps.byKey[root.key] ?? null
    readonly property int openCount: root.app ? root.app.windows.filter(c => !DockApps.isMinimized(c)).length : 0

    width: Theme.dockIconSize + 14

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.radius
        color: mouse.pressed && !mouse.dragged ? Theme.pressedBg
             : root.app?.focused ? Theme.activeBg
             : mouse.containsMouse ? Theme.hoverBg
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durFast }
        }
    }

    AppIcon {
        id: icon
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -2
        size: Theme.dockIconSize
        source: root.app?.icon ?? ""
        name: root.app?.name ?? ""
        opacity: mouse.dragged ? 0.6 : 1
        scale: mouse.containsMouse && !mouse.dragged ? 1.08 : 1

        Behavior on scale {
            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easing }
        }
    }

    // One dot per open window (up to three), accent when it has focus
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5
        spacing: 3

        Repeater {
            model: Math.min(root.openCount, 3)

            Rectangle {
                width: 4
                height: 4
                radius: 2
                color: root.app?.focused ? Theme.accent : Theme.textSecondary
            }
        }
    }

    MouseArea {
        id: mouse

        property real pressX: 0
        property bool dragged: false

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: event => {
            pressX = event.x;
            dragged = false;
            tip.visible = false;
        }

        onPositionChanged: event => {
            if (!(pressedButtons & Qt.LeftButton) || !root.list)
                return;
            if (!dragged && Math.abs(event.x - pressX) > 4) {
                dragged = true;
                root.list.dragging = true;
            }
            if (!dragged)
                return;
            const p = mapToItem(root.list.contentItem, event.x, root.height / 2);
            const target = root.list.indexAt(p.x, p.y);
            if (target >= 0 && target !== root.index)
                root.list.model.move(root.index, target, 1);
        }

        onReleased: {
            if (dragged && root.list)
                root.list.dragging = false;
        }

        onClicked: event => {
            if (dragged || !root.app)
                return;
            if (event.button === Qt.LeftButton)
                DockApps.activate(root.app);
            else if (event.button === Qt.MiddleButton)
                DockApps.launch(root.app);
            else if (event.button === Qt.RightButton)
                root.menu?.openFor(root.app, root);
        }

        onContainsMouseChanged: {
            if (containsMouse && !root.menu?.visible)
                tipDelay.restart();
            else {
                tipDelay.stop();
                tip.visible = false;
            }
        }
    }

    Timer {
        id: tipDelay
        interval: 350
        onTriggered: tip.visible = mouse.containsMouse && !mouse.pressed && !root.menu?.visible
    }

    DockTooltip {
        id: tip
        target: root
        text: root.app?.name ?? ""
    }
}
