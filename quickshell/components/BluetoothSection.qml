import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import ".."

// Adapter power, paired devices, and connect/disconnect.
ColumnLayout {
    id: root

    property bool expanded: false

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)

    readonly property var listed: {
        const ds = Bluetooth.devices.values.filter(d => d.paired || d.connected || d.bonded);
        return ds.slice().sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)).slice(0, 8);
    }

    // Discovery costs battery on peripherals; only scan while open.
    onExpandedChanged: {
        if (root.adapter && root.adapter.enabled)
            root.adapter.discovering = root.expanded;
    }

    spacing: 2

    ExpanderRow {
        glyph: {
            if (!root.adapter || !root.adapter.enabled)
                return "󰂲";
            return root.connected.length > 0 ? "󰂱" : "󰂯";
        }
        glyphColor: root.adapter?.enabled ? Theme.textPrimary : Theme.textDim
        label: "Bluetooth"
        value: {
            if (!root.adapter)
                return "unavailable";
            if (!root.adapter.enabled)
                return "off";
            if (root.connected.length === 0)
                return "on";
            if (root.connected.length === 1)
                return root.connected[0].name;
            return root.connected.length + " connected";
        }
        expandable: root.adapter !== null
        expanded: root.expanded
        onClicked: {
            if (root.adapter)
                root.expanded = !root.expanded;
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacingS
        visible: root.expanded && root.adapter !== null
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2

            Text {
                Layout.fillWidth: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
                text: "PAIRED DEVICES"
            }

            TextButton {
                label: root.adapter?.enabled ? "Adapter on" : "Adapter off"
                accented: root.adapter?.enabled ?? false
                onClicked: {
                    if (root.adapter)
                        root.adapter.enabled = !root.adapter.enabled;
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            visible: root.listed.length === 0
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            color: Theme.textDim
            text: root.adapter?.enabled ? "No paired devices" : "Adapter is off"
        }

        Repeater {
            model: root.listed

            MouseArea {
                id: devRow
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 28
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    if (modelData.connected)
                        modelData.disconnect();
                    else
                        modelData.connect();
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: devRow.containsMouse ? Theme.hoverBg : "transparent"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingS

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: devRow.modelData.connected ? Theme.accent : Theme.textDim
                        text: devRow.modelData.connected ? "󰂱" : "󰂯"
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: devRow.modelData.connected ? Theme.textPrimary : Theme.textSecondary
                        elide: Text.ElideRight
                        text: devRow.modelData.name
                    }

                    Text {
                        visible: devRow.modelData.batteryAvailable
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.textDim
                        text: Math.round(devRow.modelData.battery * 100) + "%"
                    }

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.textDim
                        text: devRow.modelData.pairing ? "pairing…" : devRow.modelData.connected ? "connected" : ""
                    }
                }
            }
        }
    }
}
