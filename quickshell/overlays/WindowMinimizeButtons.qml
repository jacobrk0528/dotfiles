import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import ".."

// A macOS-style traffic-light dot on the top-right corner of every visible
// window. Click it to hide that window:
//  - a window already on a special workspace (logs/slack/btop/media) just
//    toggles that scratchpad away, same as the SUPER+;/'/./, keybinds.
//  - any other window gets parked on special:minimized, a scratchpad that
//    exists only to hold minimized windows — MinimizedIndicator in the bar
//    brings them back.
Scope {
    id: root

    // toplevels' lastIpcObject (position, workspace) only updates on a
    // manual refresh, not automatically as windows move — see the same note
    // in services/WindowLink.qml.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            Hyprland.refreshToplevels();
            Hyprland.refreshMonitors();
        }
    }

    Variants {
        // Resolved to a plain {client, monitor, screen, isSpecial} object up
        // front so a delegate is only ever created once its target output is
        // known — assigning PanelWindow.screen after the fact (e.g. via a
        // fallback-to-null binding) trips Quickshell's own visibility
        // management into a loop.
        //
        // A client's own "visible" field is not what it sounds like — it
        // stays true even while parked on a hidden special workspace. What
        // actually says a workspace is on screen is whether some monitor's
        // activeWorkspace (regular) or specialWorkspace (special) matches
        // it, so cross-reference that instead of trusting the client.
        model: Hyprland.toplevels.values.map(t => {
            const c = t.lastIpcObject;
            if (!c)
                return null;
            const wsName = String(c.workspace?.name ?? "");
            const isSpecial = wsName.startsWith("special:");

            const mon = Hyprland.monitors.values
                .map(m => m.lastIpcObject)
                .find(m => m && (isSpecial ? m.specialWorkspace?.name : m.activeWorkspace?.name) === wsName);
            if (!mon)
                return null;

            const scr = Quickshell.screens.find(s => s.name === mon.name);
            if (!scr)
                return null;

            return { client: c, monitor: mon, screen: scr, isSpecial: isSpecial };
        }).filter(entry => entry !== null)

        PanelWindow {
            id: win

            required property var modelData
            readonly property var client: win.modelData.client
            readonly property var monitor: win.modelData.monitor
            readonly property bool isSpecial: win.modelData.isSpecial

            screen: win.modelData.screen

            anchors {
                top: true
                right: true
            }
            margins {
                top: win.client.at[1] - win.monitor.y + 10
                right: (win.monitor.x + win.monitor.width) - (win.client.at[0] + win.client.size[0]) + 10
            }

            implicitWidth: 16
            implicitHeight: 16
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-window-button"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: dot
                anchors.fill: parent
                radius: width / 2
                color: hover.containsMouse ? "#ffc93f" : "#f6bd52"
                border.width: 1
                border.color: "#c4903a"

                Behavior on color {
                    ColorAnimation { duration: 100 }
                }

                Text {
                    anchors.centerIn: parent
                    visible: hover.containsMouse
                    text: "−"
                    font.pixelSize: 11
                    font.bold: true
                    color: "#6b4f16"
                }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (win.isSpecial)
                        Hyprland.dispatch(
                            'hl.dsp.workspace.toggle_special("' +
                            win.client.workspace.name.slice("special:".length) + '")');
                    else
                        Hyprland.dispatch(
                            'hl.dsp.window.move({ workspace = "special:minimized", window = "address:' +
                            win.client.address + '" })');
                }
            }
        }
    }
}
