import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Session actions. Arrow keys or hjkl to pick, Enter to confirm.
Overlay {
    id: root

    panelName: "power"

    readonly property var actions: [
        {
            glyph: "󰌾",
            label: "Lock",
            hint: "hyprlock",
            color: Theme.accent,
            run: () => Quickshell.execDetached(["hyprlock"])
        },
        {
            glyph: "󰗽",
            label: "Log out",
            hint: "exit Hyprland",
            color: Theme.yellow,
            run: () => Hyprland.dispatch("hl.dsp.exit()")
        },
        {
            glyph: "󰤄",
            label: "Suspend",
            hint: "systemctl suspend",
            color: Theme.purple,
            run: () => Quickshell.execDetached(["systemctl", "suspend"])
        },
        {
            glyph: "󰜉",
            label: "Reboot",
            hint: "systemctl reboot",
            color: Theme.orange,
            run: () => Quickshell.execDetached(["systemctl", "reboot"])
        },
        {
            glyph: "󰐥",
            label: "Shut down",
            hint: "systemctl poweroff",
            color: Theme.red,
            run: () => Quickshell.execDetached(["systemctl", "poweroff"])
        }
    ]

    property int selected: 0

    onShownChanged: {
        if (shown) {
            selected = 0;
            keys.forceActiveFocus();
        }
    }

    function activate(i) {
        Panels.close();
        root.actions[i].run();
    }

    Item {
        implicitWidth: column.implicitWidth
        implicitHeight: column.implicitHeight

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: root.shown

            Keys.onLeftPressed: root.selected = (root.selected + root.actions.length - 1) % root.actions.length
            Keys.onRightPressed: root.selected = (root.selected + 1) % root.actions.length
            Keys.onEscapePressed: Panels.close()
            Keys.onReturnPressed: root.activate(root.selected)
            Keys.onEnterPressed: root.activate(root.selected)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_H)
                    root.selected = (root.selected + root.actions.length - 1) % root.actions.length;
                else if (event.key === Qt.Key_L)
                    root.selected = (root.selected + 1) % root.actions.length;
            }
        }

        ColumnLayout {
            id: column
            spacing: Theme.spacingXL

            Text {
                Layout.alignment: Qt.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: 15
                color: Theme.textDim
                text: "Session"
            }

            RowLayout {
                spacing: Theme.spacingL

                Repeater {
                    model: root.actions

                    Card {
                        id: tile
                        required property var modelData
                        required property int index

                        readonly property bool current: root.selected === tile.index

                        implicitWidth: 132
                        implicitHeight: 132

                        color: tile.current ? Theme.alpha(tile.modelData.color, 0.16) : Theme.panelBg
                        border.color: tile.current ? Theme.alpha(tile.modelData.color, 0.55) : Theme.pillBorder
                        scale: tile.current ? 1.05 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.durFast
                            }
                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: Theme.durFast
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: Theme.durFast
                                easing.type: Theme.easing
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                font.family: Theme.fontFamily
                                font.pixelSize: 34
                                color: tile.current ? tile.modelData.color : Theme.textSecondary
                                text: tile.modelData.glyph

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.durFast
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 1
                                color: tile.current ? Theme.textPrimary : Theme.textSecondary
                                text: tile.modelData.label
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                color: Theme.textDim
                                text: tile.modelData.hint
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = tile.index
                            onClicked: root.activate(tile.index)
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                color: Theme.textDim
                text: "←/→ or h/l to choose · Enter to confirm · Esc to cancel"
            }
        }
    }
}
