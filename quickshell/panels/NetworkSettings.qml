import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import ".."
import "../components"

ControlSettingsPane {
    id: root
    title: "Network"
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null

    Text {
        Layout.fillWidth: true
        text: root.wired ? "Ethernet connected" + (root.wired.linkSpeed > 0 ? " · " + root.wired.linkSpeed + " Mb/s" : "") : "Ethernet disconnected"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.textSecondary
    }

    NetworkSection {
        Layout.fillWidth: true
        expanded: true
        showHeader: false
        Component.onDestruction: {
            if (wifiDevice) wifiDevice.scannerEnabled = false;
        }
    }

    Text {
        visible: !root.wifi
        text: "No Wi-Fi adapter available"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: Theme.textDim
    }
}
