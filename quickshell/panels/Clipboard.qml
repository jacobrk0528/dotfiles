import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Clipboard history over cliphist. Replaces `cliphist list | wofi --dmenu`.
Overlay {
    id: root

    panelName: "clipboard"
    contentAlign: Qt.AlignTop

    // [{ id, preview, isImage }]
    property var entries: []

    onShownChanged: {
        if (shown) {
            search.text = "";
            list.currentIndex = 0;
            listProc.running = true;
            search.forceActiveFocus();
        }
    }

    readonly property var filtered: {
        const q = search.text.trim().toLowerCase();
        if (q === "")
            return root.entries;
        return root.entries.filter(e => e.preview.toLowerCase().includes(q));
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (line === "")
                        continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const preview = line.slice(tab + 1);
                    out.push({
                        id: line.slice(0, tab),
                        line: line,
                        preview: preview,
                        isImage: preview.startsWith("[[ binary data")
                    });
                }
                root.entries = out;
            }
        }
    }

    Process {
        id: copyProc
        command: ["sh", "-c", "true"]
    }

    Process {
        id: deleteProc
        stdinEnabled: true
        command: ["cliphist", "delete"]
    }

    function copy(entry) {
        if (!entry)
            return;
        Panels.close();
        // Text is forced to text/plain: wl-copy sniffs the content otherwise,
        // and anything starting with "From " is detected as application/mbox —
        // the clipboard then offers only that type and apps asking for
        // text/plain (Slack) silently refuse to paste. Images still need
        // detection, so they go through unforced.
        const sink = entry.isImage ? "wl-copy" : "wl-copy --type text/plain";
        copyProc.command = ["sh", "-c", "cliphist decode " + entry.id + " | " + sink];
        copyProc.running = true;
    }

    function remove(entry) {
        if (!entry)
            return;
        deleteProc.running = true;
        deleteProc.write(entry.line + "\n");
        deleteProc.stdinEnabled = false;

        root.entries = root.entries.filter(e => e.id !== entry.id);
        // Re-enable stdin for the next delete once the process has exited.
        reenable.restart();
    }

    Timer {
        id: reenable
        interval: 200
        onTriggered: deleteProc.stdinEnabled = true
    }

    Card {
        width: 720
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
                    text: "󰅌"
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
                        text: "Search clipboard history…"
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
                implicitHeight: Math.min(contentHeight, 440)
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
                    height: 34
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
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: row.modelData.isImage ? Theme.purple : Theme.textDim
                            text: row.modelData.isImage ? "󰋩" : "󰦨"
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            text: row.modelData.preview
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
                text: root.entries.length === 0 ? "Clipboard history is empty" : "No matches"
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
