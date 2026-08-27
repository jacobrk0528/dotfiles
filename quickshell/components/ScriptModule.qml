import Quickshell.Io
import QtQuick
import ".."

// Runs a waybar-style script on an interval and renders its JSON
// output ({text, tooltip, class}) with pango markup converted for Qt.
BarModule {
    id: root

    property string script
    property int interval: 5000

    Process {
        id: proc
        command: [root.script]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim());
                    root.text = j.text ?? "";
                    root.tooltipText = Theme.pangoToRichText(j.tooltip ?? "");
                } catch (e) {
                    // ignore partial/garbled output; keep last good state
                }
            }
        }
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }
}
