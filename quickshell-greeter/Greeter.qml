import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

// One full-screen surface per monitor. The layout deliberately mirrors
// hyprlock.conf: thin oversized clock, accent date, then a rounded translucent
// card holding the avatar ring, name and password field.
PanelWindow {
    id: root

    required property bool primary

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: Colors.base
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "greeter"
    WlrLayershell.keyboardFocus: root.primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── Background ───────────────────────────────────────────────
    // Installed alongside the QML so the greeter user never has to read
    // anything out of /home.
    Image {
        id: wallpaper
        anchors.fill: parent
        source: Qt.resolvedUrl("wallpaper.png")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready
        blurEnabled: true
        blur: 1
        blurMax: 48
        brightness: -0.45
        saturation: -0.1
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, wallpaper.status === Image.Ready ? 0.25 : 0.55)
    }

    // ── Clock ────────────────────────────────────────────────────
    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Item {
        anchors.centerIn: parent
        width: 460
        height: 1

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            y: -336
            text: Qt.formatDateTime(root.now, "HH:mm")
            color: Colors.textPrimary
            font.family: Colors.fontFamily
            font.weight: Font.ExtraLight
            font.pixelSize: 132

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.6
                shadowColor: Qt.rgba(0, 0, 0, 0.5)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: clock.bottom
            anchors.topMargin: 8
            text: Qt.formatDateTime(root.now, "dddd, MMMM d")
            color: Colors.accent
            font.family: Colors.fontFamily
            font.weight: Font.Medium
            font.pixelSize: 19
        }

        // ── Card ─────────────────────────────────────────────────
        Rectangle {
            id: card

            visible: root.primary
            anchors.horizontalCenter: parent.horizontalCenter
            y: 34
            width: 460
            height: 288
            radius: Colors.panelRadius
            color: Colors.cardBg
            border.width: 1
            border.color: Auth.failed ? Colors.alpha(Colors.red, 0.5) : Colors.border

            Behavior on border.color {
                ColorAnimation {
                    duration: Colors.durMed
                }
            }

            // Avatar ring
            Rectangle {
                id: avatar
                anchors.horizontalCenter: parent.horizontalCenter
                y: 26
                width: 74
                height: 74
                radius: 37
                color: "transparent"
                border.width: 2
                border.color: Auth.failed ? Colors.red : Colors.accent

                Behavior on border.color {
                    ColorAnimation {
                        duration: Colors.durMed
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰀄"
                    color: parent.border.color
                    font.family: Colors.fontFamily
                    font.pixelSize: 30
                }
            }

            // Username. Editable, but styled as a label until it takes focus —
            // this is a single-user machine, so the common case is never
            // touching it.
            Item {
                id: nameRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: avatar.bottom
                anchors.topMargin: 14
                width: 240
                height: 26

                TextInput {
                    id: userField
                    anchors.centerIn: parent
                    width: parent.width
                    text: Auth.user
                    onTextChanged: Auth.user = text
                    enabled: !Auth.busy && !Auth.launching
                    horizontalAlignment: TextInput.AlignHCenter
                    color: Colors.textPrimary
                    font.family: Colors.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: 17
                    selectionColor: Colors.alpha(Colors.accent, 0.35)
                    selectedTextColor: Colors.textPrimary

                    KeyNavigation.tab: passwordField
                    Keys.onReturnPressed: passwordField.forceActiveFocus()
                    Keys.onEnterPressed: passwordField.forceActiveFocus()
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: userField.activeFocus ? 200 : 0
                    height: 1
                    color: Colors.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: Colors.durMed
                            easing.type: Colors.easing
                        }
                    }
                }
            }

            // ── Password ─────────────────────────────────────────
            Rectangle {
                id: field

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: nameRow.bottom
                anchors.topMargin: 16
                width: 380
                height: 46
                radius: 10
                color: Colors.fieldBg
                border.width: 2
                border.color: Auth.failed ? Colors.red : passwordField.activeFocus ? Colors.accent : Colors.border

                Behavior on border.color {
                    ColorAnimation {
                        duration: Colors.durMed
                    }
                }

                TextInput {
                    id: passwordField

                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    enabled: !Auth.busy && !Auth.launching
                    focus: root.primary
                    color: Colors.textPrimary
                    font.family: Colors.fontFamily
                    font.pixelSize: 15
                    selectionColor: Colors.alpha(Colors.accent, 0.35)

                    KeyNavigation.tab: userField

                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onPressed: event => {
                        // The failed state survives until the next keystroke, so
                        // the red field and message are still on screen while the
                        // user works out what went wrong. Clearing on
                        // textChanged instead would undo it the instant the
                        // rejected password was wiped.
                        if (Auth.failed && event.text.length > 0) {
                            Auth.clearFailure();
                            passwordField.clear();
                        }

                        if (event.key === Qt.Key_F2) {
                            Auth.cycleSession();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            passwordField.text = "";
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: passwordField.text === "" && !Auth.busy
                    text: "Password"
                    color: Colors.gray
                    font.family: Colors.fontFamily
                    font.pixelSize: 15
                }

                // Spinner stand-in: the field pulses while greetd is thinking.
                SequentialAnimation on opacity {
                    running: Auth.busy
                    loops: Animation.Infinite
                    alwaysRunToEnd: true

                    NumberAnimation {
                        to: 0.45
                        duration: 450
                    }
                    NumberAnimation {
                        to: 1
                        duration: 450
                    }
                }
            }

            // ── Status line ──────────────────────────────────────
            Text {
                id: status
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: field.bottom
                anchors.topMargin: 12
                width: parent.width - 48
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: Auth.message
                color: Auth.failed ? Colors.red : Colors.textSecondary
                font.family: Colors.fontFamily
                font.weight: Auth.failed ? Font.Bold : Font.Normal
                font.pixelSize: 13
                opacity: Auth.message === "" ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Colors.durFast
                    }
                }
            }

            // ── Session picker ───────────────────────────────────
            MouseArea {
                id: sessionPill

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                width: sessionText.implicitWidth + 28
                height: 26
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Auth.cycleSession()

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: sessionPill.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Colors.border

                    Behavior on color {
                        ColorAnimation {
                            duration: Colors.durFast
                        }
                    }
                }

                Text {
                    id: sessionText
                    anchors.centerIn: parent
                    text: "󰧨  " + Auth.session.name
                    color: Colors.textSecondary
                    font.family: Colors.fontFamily
                    font.pixelSize: 12
                }
            }

            // Nudge on failure, the way hyprlock's field shakes.
            SequentialAnimation {
                id: shake
                running: false

                NumberAnimation {
                    target: card
                    property: "anchors.horizontalCenterOffset"
                    to: 10
                    duration: 60
                }
                NumberAnimation {
                    target: card
                    property: "anchors.horizontalCenterOffset"
                    to: -10
                    duration: 90
                }
                NumberAnimation {
                    target: card
                    property: "anchors.horizontalCenterOffset"
                    to: 0
                    duration: 90
                }
            }

            Connections {
                target: Auth

                function onFailedChanged() {
                    if (Auth.failed) {
                        shake.restart();
                        passwordField.clear();
                        passwordField.forceActiveFocus();
                    }
                }
            }
        }
    }

    function submit() {
        if (passwordField.text === "")
            return;
        Auth.submit(passwordField.text);
    }

    // ── Bottom strip ─────────────────────────────────────────────
    // uname -n, not hostname(1): the greeter's PATH is minimal.
    property string host: ""

    Process {
        running: true
        command: ["uname", "-n"]

        stdout: StdioCollector {
            onStreamFinished: root.host = text.trim()
        }
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 32
        text: "󰍹  " + root.host
        color: Colors.textDim
        font.family: Colors.fontFamily
        font.pixelSize: 13
    }

    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        visible: root.primary
        text: "Tab  user   ·   F2  session   ·   Enter  log in"
        color: Colors.textDim
        font.family: Colors.fontFamily
        font.pixelSize: 13
    }
}
