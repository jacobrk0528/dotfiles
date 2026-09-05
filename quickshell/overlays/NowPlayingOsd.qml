import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Transient track-change OSD. Shares the top-right corner with the
// notification popups and slides down below them while any are on screen.
PanelWindow {
    id: root

    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""
    screen: Quickshell.screens.find(s => s.name === root.focusedName) ?? Quickshell.screens[0]

    readonly property int baseTop: Theme.barMargin + Theme.barHeight + Theme.spacingM
    property real topOffset: root.baseTop + (OverlayStack.notifHeight > 0 ? OverlayStack.notifHeight + Theme.spacingM : 0)

    Behavior on topOffset {
        NumberAnimation {
            duration: Theme.durMed
            easing.type: Theme.easing
        }
    }

    visible: NowPlaying.active || card.opacity > 0

    anchors {
        top: true
        right: true
    }

    margins {
        top: root.topOffset
        right: Theme.barMargin
    }

    implicitWidth: 400
    implicitHeight: 88

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-nowplaying"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Card {
        id: card

        width: parent.width
        height: parent.height

        opacity: NowPlaying.active ? 1 : 0
        // Slides in from the right like the notification cards it sits under.
        x: NowPlaying.active ? 0 : 40

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durMed
                easing.type: Theme.easing
            }
        }

        Behavior on x {
            NumberAnimation {
                duration: Theme.durMed
                easing.type: Theme.easing
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            ClippingRectangle {
                implicitWidth: 56
                implicitHeight: 56
                radius: 8
                color: Theme.alpha(Theme.text, 0.08)

                Image {
                    id: art
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Chrome hands out remote https art as often as a file URL.
                    source: NowPlaying.artUrl
                }

                // Covers both "no art" and a URL that failed to load.
                Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    color: Theme.textDim
                    text: "󰎈"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    color: Theme.alpha(Theme.text, 0.9)
                    elide: Text.ElideRight
                    text: NowPlaying.title
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.alpha(Theme.text, 0.55)
                    elide: Text.ElideRight
                    text: NowPlaying.artist
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    color: Theme.accent
                    elide: Text.ElideRight
                    text: NowPlaying.identity
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: 18
                color: Theme.accent
                text: "󰝚"
            }
        }
    }
}
