pragma Singleton
import Quickshell
import QtQuick

// Super+A (hypr/hyprland.lua → quickshell:jev) asks the dock on the focused monitor to
// focus its artoo prompt (dock/JevPrompt.qml).
Singleton {
    signal requested
}
