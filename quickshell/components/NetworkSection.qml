import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import ".."

// Wi-Fi / wired status with an expandable network list.
ColumnLayout {
    id: root

    property bool expanded: false

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null

    readonly property var activeWifi: wifiDevice?.networks?.values?.find(n => n.connected) ?? null

    readonly property var visibleNetworks: {
        const ns = root.wifiDevice?.networks?.values ?? [];
        // Strongest first, connected pinned to the top.
        return ns.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)).slice(0, 8);
    }

    // Scanning is only worth the radio time while the list is open.
    onExpandedChanged: {
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = root.expanded;
    }

    spacing: 2

    function signalGlyph(strength) {
        if (strength >= 75)
            return "󰤨";
        if (strength >= 50)
            return "󰤥";
        if (strength >= 25)
            return "󰤢";
        return "󰤟";
    }

    ExpanderRow {
        glyph: {
            if (root.wiredDevice?.connected)
                return "󰈀";
            if (root.activeWifi)
                return root.signalGlyph(root.activeWifi.signalStrength);
            return "󰤭";
        }
        glyphColor: (root.wiredDevice?.connected || root.activeWifi) ? Theme.textPrimary : Theme.orange
        label: {
            if (root.wiredDevice?.connected)
                return "Ethernet";
            if (root.activeWifi)
                return root.activeWifi.name;
            return "Disconnected";
        }
        value: {
            if (root.wiredDevice?.connected && root.wiredDevice.linkSpeed > 0)
                return root.wiredDevice.linkSpeed + " Mb/s";
            if (root.activeWifi)
                return root.activeWifi.signalStrength + "%";
            return "";
        }
        expandable: root.wifiDevice !== null
        expanded: root.expanded
        onClicked: {
            if (root.wifiDevice)
                root.expanded = !root.expanded;
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacingS
        visible: root.expanded && root.wifiDevice !== null
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2

            Text {
                Layout.fillWidth: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
                text: "NEARBY NETWORKS"
            }

            TextButton {
                label: Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                accented: Networking.wifiEnabled
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }
        }

        Repeater {
            model: root.visibleNetworks

            MouseArea {
                id: netRow
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 28
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    if (modelData.connected)
                        modelData.disconnect();
                    else if (modelData.known)
                        modelData.connect();
                    else
                        // New networks need a passphrase; hand off to nmtui.
                        Quickshell.execDetached(["ghostty", "--title=nmtui", "-e", "nmtui-connect", modelData.name]);
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: netRow.containsMouse ? Theme.hoverBg : "transparent"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingS

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: netRow.modelData.connected ? Theme.accent : Theme.textDim
                        text: root.signalGlyph(netRow.modelData.signalStrength)
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: netRow.modelData.connected ? Theme.textPrimary : Theme.textSecondary
                        elide: Text.ElideRight
                        text: netRow.modelData.name
                    }

                    Text {
                        visible: netRow.modelData.security !== WifiSecurityType.None
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.textDim
                        text: "󰌾"
                    }

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.textDim
                        text: netRow.modelData.stateChanging ? "…" : netRow.modelData.connected ? "connected" : netRow.modelData.known ? "saved" : ""
                    }
                }
            }
        }
    }
}
