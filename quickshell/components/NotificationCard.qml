import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// One notification, used both as a floating popup and as a row in the center.
Card {
    id: root

    required property var notif
    // Popups count down and dismiss themselves; center entries stay put.
    property bool isPopup: false

    readonly property color urgencyColor: {
        if (!notif)
            return Theme.accent;
        if (notif.urgency === NotificationUrgency.Critical)
            return Theme.red;
        if (notif.urgency === NotificationUrgency.Low)
            return Theme.gray;
        return Theme.accent;
    }

    implicitHeight: layout.implicitHeight + Theme.spacingL * 2

    // Urgency stripe down the left edge.
    Rectangle {
        width: 3
        radius: 2
        color: root.urgencyColor
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            leftMargin: 1
            topMargin: Theme.spacingM
            bottomMargin: Theme.spacingM
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                Notifs.close(root.notif);
                return;
            }
            const def = root.notif.actions.find(a => a.identifier === "default");
            if (def) {
                def.invoke();
                Notifs.close(root.notif);
            }
        }
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        anchors.leftMargin: Theme.spacingL + 4
        spacing: Theme.spacingM

        IconImage {
            visible: source != ""
            source: {
                if (root.notif?.image)
                    return root.notif.image;
                if (root.notif?.appIcon)
                    return Quickshell.iconPath(root.notif.appIcon, true);
                return "";
            }
            implicitSize: 32
            Layout.alignment: Qt.AlignTop
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    text: root.notif?.summary ?? ""
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.textDim
                    text: root.notif?.appName ?? ""
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                maximumLineCount: 5
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: root.notif?.body ?? ""
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            RowLayout {
                Layout.topMargin: 4
                spacing: Theme.spacingS
                visible: repeater.count > 0

                Repeater {
                    id: repeater
                    model: root.notif?.actions ?? []

                    TextButton {
                        required property var modelData
                        visible: modelData.identifier !== "default"
                        label: modelData.text
                        onClicked: {
                            modelData.invoke();
                            Notifs.close(root.notif);
                        }
                    }
                }
            }
        }

        IconButton {
            glyph: "󰅖"
            opacity: hover.containsMouse ? 1 : 0
            Layout.alignment: Qt.AlignTop
            onClicked: Notifs.close(root.notif)

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.durFast
                }
            }
        }
    }

    // How long this popup lives. Captured once: deriving the animation's
    // duration from the bar's own progress made it retarget on every frame,
    // so popups never expired.
    readonly property int lifetime: root.isPopup ? Notifs.timeoutFor(root.notif) : 0

    // Remaining-time bar along the bottom edge.
    Rectangle {
        id: timebar
        visible: root.isPopup
        height: 2
        radius: 1
        color: Theme.alpha(root.urgencyColor, 0.5)
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: Theme.spacingM
            bottomMargin: 5
        }

        property real fraction: 1
        width: (root.width - Theme.spacingM * 2) * fraction
    }

    NumberAnimation {
        target: timebar
        property: "fraction"
        running: root.isPopup
        paused: hover.containsMouse
        from: 1
        to: 0
        duration: root.lifetime
        onFinished: {
            if (root.isPopup)
                Notifs.dismissPopup(root.notif);
        }
    }
}
