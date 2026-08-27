import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Keyboard-driven app launcher over the XDG desktop entries.
Overlay {
    id: root

    panelName: "launcher"
    contentAlign: Qt.AlignTop

    // Reset state each time the panel opens.
    onShownChanged: {
        if (shown) {
            search.text = "";
            list.currentIndex = 0;
            search.forceActiveFocus();
        }
    }

    readonly property var entries: {
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        const q = search.text.trim().toLowerCase();

        if (q === "")
            return all.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, 60);

        // Rank: name prefix > name substring > generic/comment/keyword hit.
        const scored = [];
        for (const e of all) {
            const name = e.name.toLowerCase();
            const extra = ((e.genericName ?? "") + " " + (e.comment ?? "") + " " + (e.keywords ?? []).join(" ")).toLowerCase();

            let score = -1;
            if (name.startsWith(q))
                score = 0;
            else if (name.includes(q))
                score = 1;
            else if (extra.includes(q))
                score = 2;

            if (score >= 0)
                scored.push({
                    entry: e,
                    score: score
                });
        }

        scored.sort((a, b) => a.score - b.score || a.entry.name.localeCompare(b.entry.name));
        return scored.map(s => s.entry).slice(0, 40);
    }

    function launch(entry) {
        if (!entry)
            return;
        Panels.close();
        entry.execute();
    }

    Card {
        width: 620
        height: layout.implicitHeight + Theme.spacingL * 2

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            // ── Search field ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.accent
                    text: "󰍉"
                }

                TextInput {
                    id: search

                    Layout.fillWidth: true
                    focus: true

                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.textPrimary
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.textPrimary
                    clip: true

                    onTextChanged: list.currentIndex = 0

                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onEscapePressed: Panels.close()
                    Keys.onReturnPressed: root.launch(root.entries[list.currentIndex])
                    Keys.onEnterPressed: root.launch(root.entries[list.currentIndex])

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        font: search.font
                        color: Theme.textDim
                        text: "Search applications…"
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                    text: root.entries.length + " result" + (root.entries.length === 1 ? "" : "s")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            // ── Results ──────────────────────────────────────────
            ListView {
                id: list

                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, 420)
                visible: root.entries.length > 0

                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: Theme.durFast
                model: root.entries

                delegate: MouseArea {
                    id: row

                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: 46
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: list.currentIndex = index
                    onClicked: root.launch(modelData)

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
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
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingM

                        IconImage {
                            implicitSize: 28
                            source: Quickshell.iconPath(row.modelData.icon, true)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 1
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                text: row.modelData.name
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.textDim
                                elide: Text.ElideRight
                                text: row.modelData.genericName || row.modelData.comment || ""
                            }
                        }

                        Text {
                            visible: list.currentIndex === row.index
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            color: Theme.textDim
                            text: "↵"
                        }
                    }
                }
            }

            // ── Empty state ──────────────────────────────────────
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingL
                Layout.bottomMargin: Theme.spacingL
                visible: root.entries.length === 0
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textDim
                text: "No matching applications"
            }
        }
    }
}
