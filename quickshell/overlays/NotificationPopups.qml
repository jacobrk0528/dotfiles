import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import ".."
import "../components"
import "../services"

// Floating notification stack. Follows whichever monitor has focus so
// notifications always appear where you are looking.
PanelWindow {
    id: root

    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""
    screen: Quickshell.screens.find(s => s.name === root.focusedName) ?? Quickshell.screens[0]

    visible: Notifs.popups.length > 0

    anchors {
        top: true
        right: true
    }

    margins {
        top: Theme.barMargin + Theme.barHeight + Theme.spacingM
        right: Theme.barMargin
    }

    implicitWidth: 400
    implicitHeight: Math.max(1, column.implicitHeight)

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Lets the now-playing OSD stack below the notifications rather than
    // under them, in the same corner.
    Binding {
        target: OverlayStack
        property: "notifHeight"
        value: root.visible ? column.implicitHeight : 0
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.spacingM

        Repeater {
            model: Notifs.popups

            NotificationCard {
                required property var modelData

                notif: modelData
                isPopup: true
                width: column.width

                // Slide in from the right, fade out on the way out.
                ParallelAnimation {
                    running: true
                    NumberAnimation {
                        target: parent
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.durMed
                        easing.type: Theme.easing
                    }
                    NumberAnimation {
                        target: parent
                        property: "x"
                        from: 60
                        to: 0
                        duration: Theme.durMed
                        easing.type: Theme.easing
                    }
                }
            }
        }
    }
}
