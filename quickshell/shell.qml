//@ pragma UseQApplication
import Quickshell
import QtQuick
import "overlays"
import "panels"
import "desktop"

ShellRoot {
    // Status bar on every monitor
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    // Wallpaper, drawn beneath everything
    Variants {
        model: Quickshell.screens

        Wallpaper {}
    }

    // Wallpaper-layer widgets
    Variants {
        model: Theme.desktopMonitor === "" ? Quickshell.screens : Quickshell.screens.filter(s => s.name === Theme.desktopMonitor)

        DesktopWidgets {}
    }

    // Hyprland global shortcuts → panel state
    Shortcuts {}

    // Transient surfaces (follow the focused monitor)
    NotificationPopups {}

    Osd {}

    NowPlayingOsd {}

    WindowMinimizeButtons {}

    // Panels
    NotificationCenter {}
    Launcher {}
    ControlCenter {}
    PowerMenu {}
    Cheatsheet {}
    Clipboard {}
    Wallpapers {}
    Ai {}
    HomeAssistant {}
}
