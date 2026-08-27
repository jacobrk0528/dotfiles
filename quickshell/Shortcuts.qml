import Quickshell
import Quickshell.Hyprland
import QtQuick
import "services"

// Hyprland global shortcuts. Bound in hypr/hyprland.lua via
// hl.dsp.global("quickshell:<name>") — no subprocess round-trip.
Scope {
    Component.onCompleted: console.log("[shell] global shortcuts registered")

    GlobalShortcut {
        appid: "quickshell"
        name: "launcher"
        description: "Open the app launcher"
        onPressed: Panels.toggle("launcher")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "control"
        description: "Open the control center"
        onPressed: Panels.toggle("control")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "notifications"
        description: "Open the notification center"
        onPressed: Panels.toggle("notifications")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "clipboard"
        description: "Open clipboard history"
        onPressed: Panels.toggle("clipboard")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "wallpapers"
        description: "Open the wallpaper picker"
        onPressed: Panels.toggle("wallpapers")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "power"
        description: "Open the power menu"
        onPressed: Panels.toggle("power")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "cheatsheet"
        description: "Show the keybind cheatsheet"
        onPressed: Panels.toggle("cheatsheet")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "dismissNotifications"
        description: "Dismiss visible notification popups"
        onPressed: Notifs.clearPopups()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "closePanels"
        description: "Close any open shell panel"
        onPressed: Panels.close()
    }
}
