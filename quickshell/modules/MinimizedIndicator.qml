import Quickshell.Hyprland
import QtQuick
import ".."
import "../components"

// Count of windows parked on special:minimized (via the top-right dot in
// overlays/WindowMinimizeButtons.qml). Collapses to nothing when there's
// nothing minimized; click toggles special:minimized back into view.
BarModule {
    id: root

    readonly property int count: Hyprland.toplevels.values.filter(
        t => String(t.lastIpcObject?.workspace?.name ?? "") === "special:minimized"
    ).length

    icon: "󰖰"
    text: root.count > 0 ? String(root.count) : ""

    tooltipText: root.count === 1 ? "1 minimized window" : root.count + " minimized windows"

    onLeftClicked: Hyprland.dispatch('hl.dsp.workspace.toggle_special("minimized")')

    // toplevels' lastIpcObject only updates on a manual refresh, not
    // automatically as windows move — see the same note in
    // services/WindowLink.qml.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            Hyprland.refreshToplevels();
        }
    }
}
