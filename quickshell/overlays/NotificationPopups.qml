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
    // Hyprland gives an OnDemand layer surface keyboard focus as soon as it
    // maps, which would yank focus away from whatever you're typing in every
    // time a popup appears. So stay at None and only flip to OnDemand while
    // an inline reply field (NotificationCard) is actually focused.
    property bool wantKeyboard: false
    WlrLayershell.keyboardFocus: wantKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function refreshKeyboard() {
        let want = false;
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (item && item.replyActive)
                want = true;
        }
        root.wantKeyboard = want;
    }

    onVisibleChanged: {
        if (!visible)
            wantKeyboard = false;
    }

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
            id: repeater
            model: Notifs.popups

            NotificationCard {
                required property var modelData

                notif: modelData
                isPopup: true
                width: column.width

                onReplyActiveChanged: root.refreshKeyboard()
                // Re-evaluate after this card is gone, not while it still counts.
                Component.onDestruction: Qt.callLater(root.refreshKeyboard)

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
