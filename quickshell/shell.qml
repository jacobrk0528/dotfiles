//@ pragma UseQApplication
import Quickshell
import QtQuick
import "overlays"
import "panels"
import "desktop"
import "dock"

ShellRoot {
    // Status bar on every monitor
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    // App dock on every monitor
    Variants {
        model: Quickshell.screens

        Dock {}
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


    // Panels
    NotificationCenter {}
    Launcher {}
    DockPicker {}
    ControlCenter {}
    PowerMenu {}
    Cheatsheet {}
    Clipboard {}
    Wallpapers {}
    Ai {}
    HomeAssistant {}
}
