import QtQuick
import ".."

// Full-width rounded background shared by the top bar and the dock, tinted
// like a Ghostty window (same base colour and background-opacity). Hyprland
// blurs it via the quickshell-bar layer rule.
Rectangle {
    anchors.fill: parent
    radius: Theme.panelRadius
    color: Theme.alpha(Theme.base, 0.75)
    border.color: Theme.pillBorder
    border.width: 1
}
