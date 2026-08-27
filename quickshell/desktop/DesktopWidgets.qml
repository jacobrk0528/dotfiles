import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// Wallpaper-layer widgets across the top of the screen: system meters on the
// left, clock in the middle, media stack on the right. Sits above the
// wallpaper and below every window.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Bottom, not Background: the wallpaper owns Background, and two surfaces
    // on the same layer stack by creation order rather than by intent.
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Only the media controls take clicks; everything else is click-through.
    mask: Region {
        item: mediaColumn
    }

    // First-seen order, not sorted by playback state: a card must not move out
    // from under the cursor when it is paused or resumed.
    readonly property var players: MediaOrder.players

    // Clear of the bar: 32px tall with a 12px margin.
    readonly property int topInset: Theme.barMargin * 2 + Theme.barHeight + Theme.spacingXL

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ── System meters, top left ──────────────────────────────────
    WidgetPanel {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 48
        anchors.topMargin: root.topInset

        width: 330 + padding * 2

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            spacing: Theme.spacingS

            Text {
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.accent
                text: SysInfo.user + "@" + SysInfo.host
            }

            Text {
                Layout.fillWidth: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.alpha("#ffffff", 0.35)
                text: "· up " + SysInfo.uptime
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.alpha("#ffffff", 0.12)
        }

        StatRow {
            Layout.fillWidth: true
            label: "CPU"
            value: SysInfo.cpuUsage
            barColor: Theme.statusColor(SysInfo.cpuUsage, 60, 85)
            detail: {
                const pct = Math.round(SysInfo.cpuUsage) + "%";
                return SysInfo.cpuTemp ? pct + "  " + Math.round(SysInfo.cpuTemp) + "°C" : pct;
            }
        }

        StatRow {
            Layout.fillWidth: true
            label: "MEM"
            value: SysInfo.memPct
            barColor: Theme.statusColor(SysInfo.memPct, 70, 85)
            detail: SysInfo.memUsed.toFixed(0) + " / " + SysInfo.memTotal.toFixed(0) + " GB"
        }

        StatRow {
            Layout.fillWidth: true
            visible: SysInfo.gpu !== null
            label: "GPU"
            value: SysInfo.gpuUtil
            barColor: Theme.statusColor(SysInfo.gpuUtil, 60, 85)
            detail: Math.round(SysInfo.gpuUtil) + "%  " + Math.round(SysInfo.gpuTemp) + "°C"
        }

        StatRow {
            Layout.fillWidth: true
            visible: SysInfo.gpu !== null
            label: "VRAM"
            value: SysInfo.vramPct
            barColor: Theme.statusColor(SysInfo.vramPct, 70, 90)
            detail: (SysInfo.gpu?.vramUsed ?? 0).toFixed(1) + " / " + (SysInfo.gpu?.vramTotal ?? 0).toFixed(0) + " GB"
        }

        StatRow {
            Layout.fillWidth: true
            label: "DISK"
            value: SysInfo.diskPct
            barColor: Theme.statusColor(SysInfo.diskPct, 75, 90)
            detail: SysInfo.diskUsed.toFixed(0) + " / " + SysInfo.diskTotal.toFixed(0) + " GB"
        }
    }

    // ── Clock, top centre ────────────────────────────────────────
    WidgetPanel {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.topInset - Theme.spacingM

        padding: Theme.spacingXL
        spacing: -8

        Text {
            Layout.alignment: Qt.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 92
            font.weight: Font.Light
            color: Theme.alpha("#ffffff", 0.92)
            text: Qt.formatDateTime(clock.date, "HH:mm")
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 17
            color: Theme.alpha("#ffffff", 0.55)
            text: Qt.formatDate(clock.date, "dddd, MMMM d")
        }
    }

    // ── Media stack, top right ───────────────────────────────────
    ColumnLayout {
        id: mediaColumn

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 48
        anchors.topMargin: root.topInset

        width: 380
        spacing: Theme.spacingL

        Repeater {
            model: root.players

            WidgetPanel {
                required property var modelData
                Layout.fillWidth: true

                MediaCard {
                    Layout.fillWidth: true
                    player: parent.parent.modelData
                }
            }
        }
    }
}
