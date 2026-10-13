pragma Singleton
import Quickshell
import QtQuick

// One main overlay, with an optional settings pane inside the control center.
Singleton {
    id: root

    // "" | "launcher" | "control" | "notifications" | "power" | "cheatsheet" | "ai" | "homeassistant" | "dockpicker" | "dictation-history" | "jev-history"
    property string open: ""
    property Component settingsComponent: null

    onOpenChanged: {
        if (open !== "control")
            settingsComponent = null;
    }

    function showSettings(component) {
        root.open = "control";
        root.settingsComponent = component;
    }

    function closeSettings() {
        root.settingsComponent = null;
    }

    function dismiss() {
        if (root.settingsComponent !== null)
            closeSettings();
        else
            close();
    }

    readonly property bool anyOpen: open !== ""

    function toggle(name) {
        root.open = root.open === name ? "" : name;
    }

    function show(name) {
        root.open = name;
    }

    function close() {
        root.open = "";
    }
}
