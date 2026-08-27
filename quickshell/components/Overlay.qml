import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import ".."
import "../services"

// Full-screen scrim hosting one panel. Appears on the focused monitor,
// takes keyboard focus, and closes on Escape or a click outside its content.
PanelWindow {
    id: root

    // Panels.open value this overlay responds to.
    required property string panelName
    default property alias content: container.data

    // Where the panel content sits within the scrim.
    property int contentAlign: Qt.AlignCenter

    readonly property bool shown: Panels.open === panelName

    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""
    screen: Quickshell.screens.find(s => s.name === root.focusedName) ?? Quickshell.screens[0]

    visible: shown || closeAnim.running

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-overlay"
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Dimmed backdrop; clicking it dismisses the panel.
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                id: closeAnim
                duration: Theme.durMed
                easing.type: Theme.easing
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Panels.close()
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: root.shown

        Keys.onEscapePressed: Panels.close()

        Item {
            id: container

            anchors.horizontalCenter: {
                if (root.contentAlign & Qt.AlignLeft || root.contentAlign & Qt.AlignRight)
                    return undefined;
                return parent.horizontalCenter;
            }
            anchors.verticalCenter: {
                if (root.contentAlign & Qt.AlignTop || root.contentAlign & Qt.AlignBottom)
                    return undefined;
                return parent.verticalCenter;
            }
            anchors.left: root.contentAlign & Qt.AlignLeft ? parent.left : undefined
            anchors.right: root.contentAlign & Qt.AlignRight ? parent.right : undefined
            anchors.top: root.contentAlign & Qt.AlignTop ? parent.top : undefined
            anchors.bottom: root.contentAlign & Qt.AlignBottom ? parent.bottom : undefined
            anchors.margins: Theme.barMargin + Theme.barHeight + Theme.spacingM

            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            width: implicitWidth
            height: implicitHeight

            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.96

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.durMed
                    easing.type: Theme.easing
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.durMed
                    easing.type: Theme.easing
                }
            }
        }
    }
}
