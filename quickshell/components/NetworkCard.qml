import QtQuick
import Quickshell.Networking
import ".."
import "../services"

ControlOption {
    id: root
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var connection: wifi?.networks?.values?.find(n => n.connected) ?? null
    label: wired ? "Ethernet" : "Wi-Fi"
    glyph: wired ? "󰈀" : Networking.wifiEnabled ? "󰤨" : "󰤭"
    subtitle: wired ? (wired.linkSpeed > 0 ? wired.linkSpeed + " Mb/s" : "Connected")
                    : connection ? connection.name : wifi ? (Networking.wifiEnabled ? "On" : "Off") : "Unavailable"
    accented: wired !== null || (wifi !== null && Networking.wifiEnabled)
    onActivated: {
        // Wired connectivity has no radio switch; open its details instead.
        if (wired || !wifi) Panels.showSettings(settingsComponent);
        else Networking.wifiEnabled = !Networking.wifiEnabled;
    }
}
