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
    // True while the inline reply field has focus; the popup window uses
    // this to decide whether to request keyboard input from the compositor.
    readonly property bool replyActive: replyInput.activeFocus

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

    function sendReply() {
        const text = replyInput.text.trim();
        if (text.length === 0)
            return;
        root.notif.sendInlineReply(text);
        Notifs.close(root.notif);
    }

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

    // Tracks card-wide hover for the fade-in buttons below. A plain
    // MouseArea only reports containsMouse for whichever overlapping
    // MouseArea is topmost, so it drops to false — and the buttons vanish —
    // the instant the cursor crosses onto one of the IconButtons (which are
    // MouseAreas themselves). HoverHandler doesn't grab hover exclusively,
    // so it keeps reporting hovered while the cursor is over a child.
    HoverHandler {
        id: cardHover
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

                IconButton {
                    readonly property string appKey: Notifs.appKey(root.notif?.appName ?? "", root.notif?.summary ?? "")

                    glyph: Notifs.isPriority(appKey) ? "󰓎" : "󰓒"
                    glyphSize: 12
                    glyphColor: Notifs.isPriority(appKey) ? Theme.accent : Theme.textSecondary
                    opacity: cardHover.hovered || Notifs.isPriority(appKey) ? 1 : 0
                    visible: (root.notif?.appName ?? "") !== ""
                    onClicked: {
                        if (Notifs.isPriority(appKey))
                            Notifs.unmarkPriority(appKey);
                        else
                            Notifs.markPriority(appKey);
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.durFast
                        }
                    }
                }

                IconButton {
                    glyph: "󰂛"
                    glyphSize: 12
                    opacity: cardHover.hovered ? 1 : 0
                    visible: (root.notif?.appName ?? "") !== ""
                    onClicked: {
                        Notifs.blockApp(Notifs.appKey(root.notif.appName, root.notif.summary));
                        Notifs.close(root.notif);
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.durFast
                        }
                    }
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
                text: Notifs.decodeBody(root.notif?.body ?? "")
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            RowLayout {
                Layout.topMargin: 4
                spacing: Theme.spacingS
                visible: repeater.count > 0

                Repeater {
                    id: repeater
                    // A sender with inline reply typically also ships a discrete
                    // "Reply" action for daemons that can't render a text field;
                    // drop it since our own field below replaces it.
                    model: (root.notif?.actions ?? []).filter(a => a.identifier !== "default" && !(root.notif?.hasInlineReply && /reply/i.test(a.text)))

                    TextButton {
                        required property var modelData
                        label: modelData.text
                        onClicked: {
                            modelData.invoke();
                            Notifs.close(root.notif);
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: Theme.spacingS
                visible: root.notif?.hasInlineReply ?? false

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.radius
                    color: Theme.widgetBg
                    border.width: 1
                    border.color: replyInput.activeFocus ? Theme.accent : Theme.widgetBorder

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Theme.durFast
                        }
                    }

                    TextInput {
                        id: replyInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.textPrimary
                        selectionColor: Theme.alpha(Theme.accent, 0.35)
                        selectedTextColor: Theme.textPrimary

                        Keys.onReturnPressed: root.sendReply()
                        Keys.onEnterPressed: root.sendReply()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: replyInput.text === ""
                            font: replyInput.font
                            color: Theme.textDim
                            text: root.notif?.inlineReplyPlaceholder || "Reply…"
                        }
                    }
                }

                TextButton {
                    label: "Send"
                    accented: true
                    onClicked: root.sendReply()
                }
            }
        }

        IconButton {
            glyph: "󰅖"
            opacity: cardHover.hovered ? 1 : 0
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
        paused: cardHover.hovered || replyInput.activeFocus
        from: 1
        to: 0
        duration: root.lifetime
        onFinished: {
            if (root.isPopup)
                Notifs.dismissPopup(root.notif);
        }
    }
}
