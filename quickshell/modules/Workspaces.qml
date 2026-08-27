import Quickshell.Hyprland
import QtQuick
import ".."

// Workspace switching goes through the hyprland.lua custom dispatchers
// (hl.dsp.*) — this replaces the hypr_ipc_proxy.py translation layer
// that waybar needed.
Item {
    id: root

    property var bar

    implicitWidth: row.implicitWidth + 8

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                Hyprland.dispatch('hl.dsp.focus({ workspace = "e+1" })');
            else if (wheel.angleDelta.y < 0)
                Hyprland.dispatch('hl.dsp.focus({ workspace = "e-1" })');
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: Hyprland.workspaces.values.filter(ws => ws.id > 0)

            Rectangle {
                id: wsButton
                required property HyprlandWorkspace modelData

                width: wsLabel.implicitWidth + 24
                height: wsLabel.implicitHeight + 4
                anchors.verticalCenter: parent.verticalCenter
                radius: 6

                color: modelData.urgent ? Theme.wsUrgentBg
                     : modelData.active ? Theme.wsActiveBg
                     : wsMouse.containsMouse ? Theme.wsHoverBg
                     : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                Text {
                    id: wsLabel
                    anchors.centerIn: parent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    text: wsButton.modelData.name
                    color: wsButton.modelData.urgent ? "#ffffff"
                         : wsButton.modelData.active ? Theme.wsActiveFg
                         : wsMouse.containsMouse ? Theme.wsHoverFg
                         : Theme.textDim
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Hyprland.dispatch(
                        "hl.dsp.focus({ workspace = " + wsButton.modelData.id + " })")
                }
            }
        }
    }
}
