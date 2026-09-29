import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "components"
import "modules"

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: 12
        left: 12
        right: 12
    }

    implicitHeight: Theme.barHeight
    color: "transparent"

    WlrLayershell.namespace: "quickshell-bar"

    BarSurface {}

    Item {
        anchors.fill: parent
        anchors.topMargin: Theme.barPaddingV
        anchors.bottomMargin: Theme.barPaddingV
        anchors.leftMargin: Theme.barPaddingH
        anchors.rightMargin: Theme.barPaddingH

        // ── Left pill: workspaces ────────────────────────────────────
        Pill {
            anchors.left: parent.left
            height: parent.height

            Workspaces {
                bar: bar
                Layout.fillHeight: true
            }

            MinimizedIndicator {
                Layout.fillHeight: true
            }

            DictationModule {
                bar: bar
                Layout.fillHeight: true
            }
        }

        // ── Center pill: clock ───────────────────────────────────────
        Pill {
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            horizontalPadding: 16

            ClockModule {
                bar: bar
                Layout.fillHeight: true
            }
        }

        // ── Right pill: network, volume, notifications, tray ─────
        Pill {
            anchors.right: parent.right
            height: parent.height

            ScriptModule {
                bar: bar
                icon: ""
                script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/network_status"
                interval: 5000
                Layout.fillHeight: true
            }

            Separator {}

            AudioModule {
                bar: bar
                Layout.fillHeight: true
            }

            Separator {}

            NotifModule {
                bar: bar
                Layout.fillHeight: true
            }

            Separator {}

            TrayModule {
                bar: bar
                Layout.fillHeight: true
            }
        }
    }

    component Separator: Rectangle {
        implicitWidth: 1
        Layout.fillHeight: true
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        color: Theme.separator
    }
}
