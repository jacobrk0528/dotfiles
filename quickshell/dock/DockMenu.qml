import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// Right-click menu for a dock tile, modeled on the macOS Dock's: the app's
// windows, then new window / keep in dock / close. One per dock.
//
// A full-screen transparent overlay (like components/Overlay.qml, minus the
// scrim) rather than a popup, so a click anywhere else or Escape dismisses it.
PanelWindow {
    id: root

    property var app: null
    // Horizontal centre of the tile that opened it, in dock coordinates
    property real tileX: 0

    readonly property var windows: root.app?.windows ?? []

    function openFor(app, tile) {
        root.app = app;
        root.tileX = tile.mapToItem(null, tile.width / 2, 0).x + Theme.barMargin;
        root.visible = true;
    }

    function close() {
        root.visible = false;
    }

    function run(action) {
        root.close();
        action();
    }

    visible: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-dock-menu"
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()

        Rectangle {
            id: box

            width: Math.min(Math.max(column.implicitWidth, 200), 420) + 12
            height: column.implicitHeight + 12
            x: Math.max(Theme.barMargin, Math.min(root.tileX - width / 2, root.width - width - Theme.barMargin))
            y: root.height - height - Theme.barMargin - Theme.dockHeight - 8

            color: Theme.panelBg
            border.color: Theme.tooltipBorder
            border.width: 1
            radius: Theme.radius

            // Swallow clicks on the box itself so they don't reach the catcher
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            ColumnLayout {
                id: column
                anchors.fill: parent
                anchors.margins: 6
                spacing: 0

                Header {
                    visible: root.windows.length > 0
                    text: "Windows"
                }

                Repeater {
                    model: root.windows

                    MenuRow {
                        required property var modelData
                        readonly property string ws: String(modelData.workspace?.name ?? "")

                        text: (modelData.title || root.app?.name || "Window")
                        detail: ws === "special:minimized" ? "minimized"
                              : ws.startsWith("special:") ? ws.slice("special:".length)
                              : ws
                        onActivated: root.run(() => DockApps.focusWindow(modelData))
                    }
                }

                Divider {
                    visible: root.windows.length > 0
                }

                MenuRow {
                    visible: !!(root.app?.entry || root.app?.exec)
                    text: "New window"
                    onActivated: root.run(() => DockApps.launch(root.app))
                }

                MenuRow {
                    visible: !!(root.app?.entry || root.app?.exec)
                    text: root.app?.pinned ? "Remove from Dock" : "Keep in Dock"
                    onActivated: {
                        const app = root.app;
                        root.run(() => DockApps.setPinned(app, !app.pinned));
                    }
                }

                MenuRow {
                    visible: root.windows.length > 0
                    text: root.windows.length > 1 ? "Close " + root.windows.length + " windows" : "Close"
                    danger: true
                    onActivated: {
                        const windows = root.windows;
                        root.run(() => windows.forEach(c => DockApps.close(c)));
                    }
                }
            }
        }
    }

    component Header: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: Theme.textDim
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 1
        color: Theme.separator
    }

    component MenuRow: MouseArea {
        id: row

        property string text
        property string detail
        property bool danger: false
        signal activated

        Layout.fillWidth: true
        implicitWidth: label.implicitWidth + detailLabel.implicitWidth + 40
        implicitHeight: 28
        hoverEnabled: true
        onClicked: row.activated()

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: row.containsMouse ? Theme.hoverBg : "transparent"
        }

        Text {
            id: label
            anchors.left: parent.left
            anchors.right: detailLabel.left
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: row.danger && row.containsMouse ? Theme.red : Theme.textPrimary
            text: row.text
        }

        Text {
            id: detailLabel
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            color: Theme.textDim
            text: row.detail
        }
    }
}
