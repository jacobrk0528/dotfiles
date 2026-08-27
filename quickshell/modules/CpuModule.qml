import Quickshell.Io
import QtQuick
import ".."
import "../components"

// Native CPU usage from /proc/stat deltas (replaces waybar's builtin cpu module).
BarModule {
    id: root

    icon: ""
    tooltipText: "CPU usage"

    property var prev: null

    Process {
        id: statProc
        command: ["cat", "/proc/stat"]

        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.split("\n").find(l => l.startsWith("cpu "));
                if (!line)
                    return;
                const f = line.trim().split(/\s+/).slice(1).map(Number);
                const idle = f[3] + f[4];
                const total = f.reduce((a, b) => a + b, 0);

                if (root.prev) {
                    const dTotal = total - root.prev.total;
                    const dIdle = idle - root.prev.idle;
                    if (dTotal > 0) {
                        const usage = Math.round(100 * (1 - dIdle / dTotal));
                        root.text = usage + "%";
                        root.tooltipText = "CPU usage: " + usage + "%";
                    }
                }
                root.prev = { total: total, idle: idle };
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statProc.running = true
    }
}
