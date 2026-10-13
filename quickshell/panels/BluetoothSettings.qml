import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import ".."
import "../components"

ControlSettingsPane {
    title: "Bluetooth"
    Text {
        visible: Bluetooth.defaultAdapter === null
        text: "No Bluetooth adapter available"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: Theme.textDim
    }
    BluetoothSection {
        Layout.fillWidth: true
        expanded: true
        showHeader: false
        Component.onDestruction: {
            if (adapter) adapter.discovering = false;
        }
    }
}
