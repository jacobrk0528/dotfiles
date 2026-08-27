import Quickshell
import QtQuick
import "../components"

// Media status via the existing mpris_status script (it mixes Hyprland
// window-title scraping with playerctl, which native Mpris can't replicate).
ScriptModule {
    id: root

    script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/mpris_status"
    interval: 2000

    onLeftClicked: Quickshell.execDetached(["playerctl", "play-pause"])
    onScrolled: delta => {
        if (delta > 0)
            Quickshell.execDetached(["playerctl", "next"]);
        else if (delta < 0)
            Quickshell.execDetached(["playerctl", "previous"]);
    }
}
