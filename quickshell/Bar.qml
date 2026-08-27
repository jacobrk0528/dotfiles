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

    implicitHeight: 32
    color: "transparent"

    WlrLayershell.namespace: "quickshell"

    // ── Left pill: workspaces + window title ─────────────────────
    Pill {
        anchors.left: parent.left
        height: parent.height

        Workspaces {
            bar: bar
            Layout.fillHeight: true
        }

        WindowTitle {
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

    // ── Right pill: status modules + tray ────────────────────────
    Pill {
        anchors.right: parent.right
        height: parent.height

        MprisModule {
            bar: bar
            Layout.fillHeight: true
        }

        Separator {}

        CpuModule {
            bar: bar
            Layout.fillHeight: true
        }

        Separator {}

        ScriptModule {
            bar: bar
            icon: "󰍛"
            script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/mem_status.sh"
            interval: 5000
            Layout.fillHeight: true
        }

        Separator {}

        ScriptModule {
            bar: bar
            icon: "󰢮"
            script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/gpu_util"
            interval: 5000
            Layout.fillHeight: true
        }

        Separator {}

        ScriptModule {
            bar: bar
            icon: ""
            script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/cpu_temp"
            interval: 5000
            Layout.fillHeight: true
        }

        Separator {}

        ScriptModule {
            bar: bar
            icon: "󰢮"
            script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/gpu_temp"
            interval: 5000
            Layout.fillHeight: true
        }

        Separator {}

        ScriptModule {
            bar: bar
            icon: "󰋊"
            script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/disk_status"
            interval: 10000
            Layout.fillHeight: true
        }

        Separator {}

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

    component Separator: Rectangle {
        implicitWidth: 1
        Layout.fillHeight: true
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        color: Theme.separator
    }
}
