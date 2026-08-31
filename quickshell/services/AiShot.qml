pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Captures the focused monitor and only then opens the AI overlay (Ai.qml),
// so the screenshot it hands to Claude is the real screen - not one already
// muddied by the overlay's own blur (hypr/hyprland.lua blurs the
// "quickshell-overlay" layer namespace). Once that layer surface is even
// mapped the blur is already baked into the next composited frame, so
// capturing after opening came out unusably blurry; capturing first and
// opening in onExited sidesteps the race entirely.
Singleton {
    id: root

    readonly property string path: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-ai-screenshot.png"
    property bool ready: false

    function captureThenOpen() {
        if (Panels.open === "ai") {
            Panels.close();
            return;
        }

        root.ready = false;
        const monitor = Hyprland.focusedMonitor?.name ?? "";
        proc.command = monitor === "" ? ["grim", root.path] : ["grim", "-o", monitor, root.path];
        proc.running = true;
    }

    Process {
        id: proc
        onExited: exitCode => {
            root.ready = exitCode === 0;
            Panels.show("ai");
        }
    }
}
