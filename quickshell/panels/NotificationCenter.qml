import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Notification history, anchored under the right end of the bar.
Overlay {
    id: root

    panelName: "notifications"
    contentAlign: Qt.AlignTop | Qt.AlignRight

    Card {
        width: 420
        height: Math.min(root.height - Theme.barHeight - Theme.barMargin * 4, layout.implicitHeight + Theme.spacingL * 2)

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            // ── Header ───────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                    color: Theme.textPrimary
                    text: "Notifications"
                }

                Rectangle {
                    visible: Notifs.count > 0
                    implicitWidth: countLabel.implicitWidth + 12
                    implicitHeight: 18
                    radius: 9
                    color: Theme.alpha(Theme.accent, 0.18)

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.accent
                        text: Notifs.count
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                IconButton {
                    glyph: Notifs.doNotDisturb ? "󰂛" : "󰂚"
                    glyphColor: Notifs.doNotDisturb ? Theme.orange : Theme.textSecondary
                    onClicked: Notifs.doNotDisturb = !Notifs.doNotDisturb
                }

                TextButton {
                    label: "Clear"
                    visible: Notifs.count > 0
                    onClicked: Notifs.clearAll()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            // ── Empty state ──────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXL
                Layout.bottomMargin: Theme.spacingXL
                visible: Notifs.count === 0
                spacing: Theme.spacingS

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 28
                    color: Theme.textDim
                    text: "󰂜"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textDim
                    text: Notifs.doNotDisturb ? "Do not disturb is on" : "No notifications"
                }
            }

            // ── History ──────────────────────────────────────────
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Notifs.count > 0
                implicitHeight: Math.min(contentHeight, 520)

                clip: true
                spacing: Theme.spacingS
                boundsBehavior: Flickable.StopAtBounds

                // Newest first
                model: Notifs.all.slice().reverse()

                delegate: NotificationCard {
                    required property var modelData
                    notif: modelData
                    width: ListView.view.width
                }
            }
        }
    }
}
