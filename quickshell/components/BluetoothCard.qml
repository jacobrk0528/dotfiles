import QtQuick
import Quickshell.Bluetooth
import ".."

ControlOption {
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)
    label: "Bluetooth"
    glyph: adapter?.enabled ? "󰂯" : "󰂲"
    subtitle: !adapter ? "Unavailable" : !adapter.enabled ? "Off"
                      : connected.length ? connected.length + " connected" : "On"
    accented: adapter?.enabled ?? false
    onActivated: {
        if (adapter) adapter.enabled = !adapter.enabled;
    }
}
