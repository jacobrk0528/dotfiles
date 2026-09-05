pragma Singleton
import Quickshell
import QtQuick

// Which full-screen overlay panel is currently open. Only one at a time,
// so opening any panel implicitly closes the others.
Singleton {
    id: root

    // "" | "launcher" | "control" | "notifications" | "power" | "cheatsheet" | "ai" | "homeassistant"
    property string open: ""

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
