import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Dictation history (SUPER+Insert), newest first: everything ptt-dictate has
// typed, read from its history.jsonl. Same shape as the clipboard panel —
// Enter copies, Del removes.
Overlay {
    id: root

    panelName: "dictation-history"
    contentAlign: Qt.AlignTop

    // [{ ts, text, when }], newest first
    property var entries: []

    onShownChanged: {
        if (shown) {
            search.text = "";
            list.currentIndex = 0;
            historyFile.reload();
            search.forceActiveFocus();
        }
    }

    readonly property var filtered: {
        const q = search.text.trim().toLowerCase();
        if (q === "")
            return root.entries;
        return root.entries.filter(e => e.text.toLowerCase().includes(q));
    }

    FileView {
        id: historyFile
        path: Quickshell.env("HOME") + "/.local/share/ptt-dictate/history.jsonl"
        blockLoading: true
        onLoaded: root.parse(text())
        onLoadFailed: root.entries = []
    }

    function parse(raw) {
        const out = [];
        for (const line of raw.split("\n")) {
            if (line.trim() === "")
                continue;
            try {
                const r = JSON.parse(line);
                if (r.text)
                    out.push({ ts: r.ts, text: r.text, when: root.formatWhen(r.ts) });
            } catch (e) {
                // skip a half-written line
            }
        }
        root.entries = out.reverse();
    }

    // "14:02" today, "Sep 28 14:02" otherwise
    function formatWhen(ts) {
        const d = new Date(ts);
        const today = new Date();
        const time = Qt.formatDateTime(d, "HH:mm");
        return d.toDateString() === today.toDateString() ? time : Qt.formatDateTime(d, "MMM d") + " " + time;
    }

    Process {
        id: copyProc
    }

    function copy(entry) {
        if (!entry)
            return;
        Panels.close();
        // text/plain forced for the same reason as the clipboard panel
        copyProc.command = ["wl-copy", "--type", "text/plain", "--", entry.text];
        copyProc.running = true;
    }

    // Drops the entry and rewrites history.jsonl without it (oldest first,
    // as the daemon appends).
    function remove(entry) {
        if (!entry)
            return;
        root.entries = root.entries.filter(e => e !== entry);
        const lines = root.entries.slice().reverse().map(e => JSON.stringify({ ts: e.ts, text: e.text }));
        historyFile.setText(lines.join("\n") + (lines.length ? "\n" : ""));
    }

    Card {
        width: 760
        height: layout.implicitHeight + Theme.spacingL * 2

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.accent
                    text: "󰍬"
                }

                TextInput {
                    id: search

                    Layout.fillWidth: true
                    focus: true

                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: Theme.textPrimary
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.textPrimary
                    clip: true

                    onTextChanged: list.currentIndex = 0

                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onEscapePressed: Panels.close()
                    Keys.onReturnPressed: root.copy(root.filtered[list.currentIndex])
                    Keys.onEnterPressed: root.copy(root.filtered[list.currentIndex])
                    Keys.onDeletePressed: root.remove(root.filtered[list.currentIndex])

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        font: search.font
                        color: Theme.textDim
                        text: "Search dictation history…"
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                    text: root.filtered.length + " item" + (root.filtered.length === 1 ? "" : "s")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            ListView {
                id: list

                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, 480)
                visible: root.filtered.length > 0

                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.filtered

                delegate: MouseArea {
                    id: row

                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: body.implicitHeight + 16
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                    onEntered: list.currentIndex = index
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton)
                            root.remove(modelData);
                        else
                            root.copy(modelData);
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: list.currentIndex === row.index ? Theme.activeBg : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.durFast
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingM

                        Text {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 8
                            Layout.preferredWidth: 96
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.textDim
                            text: row.modelData.when
                        }

                        // Two lines, so a sentence reads as more than its opening words
                        Text {
                            id: body
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textSecondary
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: row.modelData.text
                        }

                        IconButton {
                            glyph: "󰅖"
                            size: 20
                            opacity: row.containsMouse ? 1 : 0
                            hoverColor: Theme.red
                            onClicked: root.remove(row.modelData)

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.durFast
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingL
                Layout.bottomMargin: Theme.spacingL
                visible: root.filtered.length === 0
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textDim
                text: root.entries.length === 0 ? "No dictations yet" : "No matches"
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
                text: "Enter to copy · Del or middle-click to remove · Esc to close"
            }
        }
    }
}
