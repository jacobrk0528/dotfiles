import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Volume / mute overlay near the bottom of the focused monitor.
PanelWindow {
    id: root

    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""
    screen: Quickshell.screens.find(s => s.name === root.focusedName) ?? Quickshell.screens[0]

    visible: Osd.active || card.opacity > 0

    anchors {
        bottom: true
    }

    margins {
        bottom: 120
    }

    implicitWidth: 320
    implicitHeight: 72

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Card {
        id: card
        anchors.fill: parent

        opacity: Osd.active ? 1 : 0
        y: Osd.active ? 0 : 12

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durMed
                easing.type: Theme.easing
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: Theme.durMed
                easing.type: Theme.easing
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingL

            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 22
                color: Osd.muted ? Theme.orange : Theme.textPrimary
                text: {
                    if (Osd.muted)
                        return "󰖁";
                    const pct = Osd.volume * 100;
                    if (pct < 34)
                        return "󰕿";
                    if (pct < 67)
                        return "󰖀";
                    return "󰕾";
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textDim
                        elide: Text.ElideRight
                        text: Osd.muted ? "Muted" : (Osd.sink?.description ?? "Volume")
                    }

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.textPrimary
                        text: Math.round(Osd.volume * 100) + "%"
                    }
                }

                // Level bar
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 5
                    radius: 3
                    color: Theme.alpha(Theme.textPrimary, 0.1)

                    Rectangle {
                        width: parent.width * Math.min(1, Osd.volume)
                        height: parent.height
                        radius: parent.radius
                        color: Osd.muted ? Theme.orange : Theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.durFast
                                easing.type: Theme.easing
                            }
                        }
                    }
                }
            }
        }
    }
}
