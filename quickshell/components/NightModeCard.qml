import QtQuick
import ".."
import "../services"

ControlOption {
    property bool active: false
    label: "Night mode"
    glyph: "󰖔"
    subtitle: NightMode.enabled ? NightMode.temperature + "K" : "Off"
    accented: NightMode.enabled
    accentColor: Theme.orange
    onActivated: NightMode.request(["toggle"])
    onActiveChanged: {
        if (active) NightMode.request(["snapshot"]);
    }
}
