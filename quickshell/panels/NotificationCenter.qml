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

    property bool showRules: false
    property bool showHistory: false

    // "block" | "priority"
    function addRule(list, appName) {
        const name = appName.trim();
        if (name === "")
            return;
        if (list === "block")
            Notifs.blockApp(name);
        else
            Notifs.markPriority(name);
    }

    function relativeTime(ms) {
        const diff = Math.max(0, Date.now() - ms);
        const mins = Math.floor(diff / 60000);
        if (mins < 1)
            return "now";
        if (mins < 60)
            return mins + "m ago";
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return hours + "h ago";
        const days = Math.floor(hours / 24);
        if (days < 7)
            return days + "d ago";
        return Qt.formatDateTime(new Date(ms), "MMM d");
    }

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

                IconButton {
                    glyph: "󰒓"
                    glyphColor: root.showRules ? Theme.accent : Theme.textSecondary
                    onClicked: root.showRules = !root.showRules
                }

                TextButton {
                    label: root.showHistory ? "Clear history" : "Clear"
                    visible: root.showHistory ? Notifs.history.length > 0 : Notifs.count > 0
                    onClicked: root.showHistory ? Notifs.clearHistory() : Notifs.clearAll()
                }
            }

            // ── Tabs ─────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                TextButton {
                    label: "Recent"
                    accented: !root.showHistory
                    onClicked: root.showHistory = false
                }

                TextButton {
                    label: "History (" + Notifs.history.length + ")"
                    accented: root.showHistory
                    onClicked: root.showHistory = true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            // ── App rules: priority (bypasses DND) / blocked ──────
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.showRules
                spacing: Theme.spacingM

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textDim
                        text: "PRIORITY  ·  bypasses do not disturb"
                    }

                    Repeater {
                        model: Notifs.priorityApps

                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spacingS

                            Text {
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                text: modelData
                            }

                            IconButton {
                                glyph: "󰅖"
                                glyphSize: 12
                                onClicked: Notifs.unmarkPriority(modelData)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: Theme.radius
                            color: Theme.widgetBg
                            border.width: 1
                            border.color: priorityInput.activeFocus ? Theme.accent : Theme.widgetBorder

                            TextInput {
                                id: priorityInput
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textPrimary
                                selectionColor: Theme.alpha(Theme.accent, 0.35)
                                selectedTextColor: Theme.textPrimary

                                Keys.onReturnPressed: {
                                    root.addRule("priority", text);
                                    text = "";
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: priorityInput.text === ""
                                    font: priorityInput.font
                                    color: Theme.textDim
                                    text: "App name…"
                                }
                            }
                        }

                        TextButton {
                            label: "Add"
                            onClicked: {
                                root.addRule("priority", priorityInput.text);
                                priorityInput.text = "";
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textDim
                        text: "BLOCKED  ·  never shown"
                    }

                    Repeater {
                        model: Notifs.blockedApps

                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spacingS

                            Text {
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                text: modelData
                            }

                            IconButton {
                                glyph: "󰅖"
                                glyphSize: 12
                                onClicked: Notifs.unblockApp(modelData)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: Theme.radius
                            color: Theme.widgetBg
                            border.width: 1
                            border.color: blockInput.activeFocus ? Theme.accent : Theme.widgetBorder

                            TextInput {
                                id: blockInput
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textPrimary
                                selectionColor: Theme.alpha(Theme.accent, 0.35)
                                selectedTextColor: Theme.textPrimary

                                Keys.onReturnPressed: {
                                    root.addRule("block", text);
                                    text = "";
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: blockInput.text === ""
                                    font: blockInput.font
                                    color: Theme.textDim
                                    text: "App name…"
                                }
                            }
                        }

                        TextButton {
                            label: "Add"
                            onClicked: {
                                root.addRule("block", blockInput.text);
                                blockInput.text = "";
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.separator
                }
            }

            // ── Empty state ──────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXL
                Layout.bottomMargin: Theme.spacingXL
                visible: root.showHistory ? Notifs.history.length === 0 : Notifs.count === 0
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
                    text: root.showHistory ? "No history yet" : (Notifs.doNotDisturb ? "Do not disturb is on" : "No notifications")
                }
            }

            // ── Recent (live, tracked) ────────────────────────────
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.showHistory && Notifs.count > 0
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

            // ── History (permanent log, survives Clear/dismiss) ───
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.showHistory && Notifs.history.length > 0
                implicitHeight: Math.min(contentHeight, 520)

                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                // Newest first
                model: Notifs.history.slice().reverse()

                delegate: Rectangle {
                    id: histRow
                    required property var modelData

                    width: ListView.view.width
                    implicitHeight: histLayout.implicitHeight + Theme.spacingS * 2
                    radius: Theme.radius
                    color: histHover.hovered ? Theme.hoverBg : "transparent"

                    HoverHandler {
                        id: histHover
                    }

                    RowLayout {
                        id: histLayout
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS

                        IconButton {
                            glyph: histRow.modelData.marked ? "󰓎" : "󰓒"
                            glyphSize: 12
                            glyphColor: histRow.modelData.marked ? Theme.accent : Theme.textDim
                            onClicked: Notifs.toggleHistoryMark(histRow.modelData.id)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingS

                                Text {
                                    Layout.fillWidth: true
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    font.bold: true
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    text: histRow.modelData.summary || histRow.modelData.appName
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    color: Theme.textDim
                                    text: root.relativeTime(histRow.modelData.timestamp)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                text: (histRow.modelData.appName ? histRow.modelData.appName + " · " : "") + Notifs.decodeBody(histRow.modelData.body)
                            }
                        }

                        IconButton {
                            glyph: "󰅖"
                            glyphSize: 12
                            opacity: histHover.hovered ? 1 : 0
                            onClicked: Notifs.removeHistoryEntry(histRow.modelData.id)

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.durFast
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
