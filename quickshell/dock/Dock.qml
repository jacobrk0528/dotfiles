import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../modules"
import "../services"

// Bottom dock, one per monitor: media on the left, pinned + running apps in
// the middle, then minimized windows after a divider. Always visible, so it
// reserves its height like the top bar does.
PanelWindow {
    id: dock

    required property var modelData
    screen: modelData

    anchors {
        bottom: true
        left: true
        right: true
    }

    margins {
        bottom: Theme.barMargin
        left: Theme.barMargin
        right: Theme.barMargin
    }

    implicitHeight: Theme.dockHeight
    color: "transparent"

    WlrLayershell.namespace: "quickshell-bar"

    BarSurface {}

    // Right-click on empty dock space: the "Add to Dock" picker
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: Panels.show("dockpicker")
    }

    Item {
        anchors.fill: parent
        anchors.topMargin: Theme.barPaddingV
        anchors.bottomMargin: Theme.barPaddingV
        anchors.leftMargin: Theme.barPaddingH
        anchors.rightMargin: Theme.barPaddingH

        // ── Left: now playing ────────────────────────────────────────
        MprisModule {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            bar: dock
            tooltipAbove: true
            textColor: Theme.textPrimary
        }

        // ── Right: system stats ──────────────────────────────────
        Pill {
            anchors.right: parent.right
            // Mirrors the now-playing text's inset on the left (BarModule's
            // default horizontalPadding)
            anchors.rightMargin: 8
            height: parent.height
            horizontalPadding: 0
            spacing: 6
            // Pill hides itself at zero width, and hidden children report
            // zero width, so it would never come back from the moment before
            // the stats first load
            visible: true

            CpuModule {
                bar: dock
                title: "CPU"
                thresholds: [50, 80]
                tooltipAbove: true
                Layout.fillHeight: true
            }

            ScriptModule {
                bar: dock
                tooltipAbove: true
                icon: "󰍛"
                script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/mem_status.sh"
                title: "Mem"
                thresholds: [60, 85]
                interval: 5000
                Layout.fillHeight: true
            }

            ScriptModule {
                bar: dock
                tooltipAbove: true
                icon: "󰢮"
                script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/gpu_util"
                title: "GPU"
                thresholds: [60, 90]
                interval: 5000
                Layout.fillHeight: true
            }

            ScriptModule {
                bar: dock
                tooltipAbove: true
                icon: "󰔏"
                script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/cpu_temp"
                title: "CPU temp"
                thresholds: [70, 85]
                interval: 5000
                Layout.fillHeight: true
            }

            ScriptModule {
                bar: dock
                tooltipAbove: true
                icon: "󰢮"
                script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/gpu_temp"
                title: "GPU temp"
                thresholds: [70, 83]
                interval: 5000
                Layout.fillHeight: true
            }

            ScriptModule {
                bar: dock
                tooltipAbove: true
                icon: "󰋊"
                script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/disk_status"
                title: "Disk"
                thresholds: [75, 90]
                interval: 10000
                Layout.fillHeight: true
            }
        }

        // ── Center: apps | minimized windows ─────────────────────────
        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            spacing: 0

            ListView {
                id: appList

                Layout.fillHeight: true
                Layout.preferredWidth: contentWidth
                orientation: ListView.Horizontal
                interactive: false
                spacing: 2
                model: appModel

                // Set by a tile while it is being dragged; holds off syncing the
                // model so the dragged delegate isn't rebuilt out from under it.
                property bool dragging: false

                delegate: AppTile {
                    list: appList
                    menu: dockMenu
                    height: appList.height
                }

                displaced: Transition {
                    NumberAnimation { properties: "x"; duration: Theme.durFast; easing.type: Theme.easing }
                }
                move: Transition {
                    NumberAnimation { properties: "x"; duration: Theme.durFast; easing.type: Theme.easing }
                }

                onDraggingChanged: {
                    if (dragging)
                        return;
                    const keys = [];
                    for (let i = 0; i < appModel.count; i++)
                        keys.push(appModel.get(i).key);
                    DockApps.saveOrder(keys);
                    dock.sync();
                }
            }

            Rectangle {
                visible: DockApps.minimized.length > 0
                implicitWidth: 1
                Layout.fillHeight: true
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                color: Theme.pillBorder
            }

            Repeater {
                model: DockApps.minimized

                MinimizedTile {
                    Layout.fillHeight: true
                }
            }
        }
    }

    DockMenu {
        id: dockMenu
        screen: dock.screen
    }

    // ── Model sync ───────────────────────────────────────────────
    // A ListModel (not the apps array directly) so ListModel.move can reorder
    // tiles live during a drag without recreating their delegates.
    ListModel {
        id: appModel
    }

    function sync() {
        if (appList.dragging)
            return;
        const want = DockApps.apps.map(a => a.key);
        for (let i = 0; i < want.length; i++) {
            let j = -1;
            for (let k = i; k < appModel.count; k++) {
                if (appModel.get(k).key === want[i]) {
                    j = k;
                    break;
                }
            }
            if (j === -1)
                appModel.insert(i, { key: want[i] });
            else if (j !== i)
                appModel.move(j, i, 1);
        }
        if (appModel.count > want.length)
            appModel.remove(want.length, appModel.count - want.length);
    }

    Connections {
        target: DockApps
        function onAppsChanged() {
            dock.sync();
        }
    }

    Component.onCompleted: sync()
}
