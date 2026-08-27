pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Polls scripts/sysinfo and exposes the numbers to the desktop widgets.
Singleton {
    id: root

    property var data: ({})
    property int interval: 3000

    readonly property real cpuUsage: data.cpu?.usage ?? 0
    readonly property var cpuTemp: data.cpu?.temp ?? null

    readonly property real memPct: data.mem?.pct ?? 0
    readonly property real memUsed: data.mem?.used ?? 0
    readonly property real memTotal: data.mem?.total ?? 0

    readonly property real diskPct: data.disk?.pct ?? 0
    readonly property real diskUsed: data.disk?.used ?? 0
    readonly property real diskTotal: data.disk?.total ?? 0

    readonly property var gpu: data.gpu ?? null
    readonly property real gpuUtil: gpu?.util ?? 0
    readonly property real gpuTemp: gpu?.temp ?? 0
    readonly property real vramPct: gpu?.vramPct ?? 0

    readonly property string uptime: data.uptime ?? ""
    readonly property string host: data.host ?? ""
    readonly property string user: data.user ?? ""

    Process {
        id: proc
        command: [Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/sysinfo"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(text);
                } catch (e) {
                // keep the previous snapshot
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
