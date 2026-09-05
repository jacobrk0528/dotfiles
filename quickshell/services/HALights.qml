pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Home Assistant light/media control + state, shared by the SUPER+Y popup
// panel (panels/HomeAssistant.qml) and the always-on desktop widget
// (desktop/DesktopWidgets.qml). Polls ha-lights-status on a fixed interval
// regardless of whether the popup is open, since the desktop widget needs
// it live at all times.
Singleton {
    id: root

    readonly property var groups: [
        { label: "All lights", group: "all", section: "Lights" },
        { label: "Kitchen", group: "kitchen", section: "Lights" },
        { label: "Living room", group: "living_room", section: "Lights" },
        { label: "Bedroom", group: "bedroom", section: "Lights" },
        { label: "Bathroom", group: "bathroom", section: "Lights" },
        { label: "TV", group: "tv", section: "Media" }
    ]

    // group -> "on" | "off" | "mixed", populated from ha-lights-status
    property var groupStates: ({})

    function refresh() {
        statusProc.running = true;
    }

    function run(action, group) {
        // "toggle all" would otherwise flip each light individually (HA's
        // toggle service is per-entity), which can leave lights mixed. Use
        // the cached all-group state instead: any light on -> turn all off,
        // otherwise turn all on.
        if (action === "toggle" && group === "all") {
            action = root.groupStates["all"] === "on" ? "off" : "on";
        }
        Quickshell.execDetached(["/home/jkrebs/dotfiles/quickshell/scripts/ha-lights", action, group]);
        // Matter devices take a beat to report their new state back, so
        // re-poll shortly after instead of only on the fixed interval.
        refreshDelay.restart();
    }

    function setColor(group, r, g, b) {
        Quickshell.execDetached(["/home/jkrebs/dotfiles/quickshell/scripts/ha-lights", "color", group, String(r), String(g), String(b)]);
        refreshDelay.restart();
    }

    Process {
        id: statusProc
        command: ["/home/jkrebs/dotfiles/quickshell/scripts/ha-lights-status"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.groupStates = JSON.parse(text);
                } catch (e) {
                    console.log("[HALights] failed to parse ha-lights-status output:", e);
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 1500
        onTriggered: root.refresh()
    }
}
