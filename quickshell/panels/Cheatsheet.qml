import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Keybind reference, generated from hyprland.lua so it can never drift
// out of sync with the actual binds.
Overlay {
    id: root

    panelName: "cheatsheet"

    property var sections: []

    onShownChanged: {
        if (shown) {
            search.text = "";
            proc.running = true;
            search.forceActiveFocus();
        }
    }

    // Filter on both the key and the description, so "audio" finds the sink
    // switches and "super + c" finds what that chord does.
    readonly property var filtered: {
        const q = search.text.trim().toLowerCase();
        if (q === "")
            return root.sections;

        const out = [];
        for (const sec of root.sections) {
            const hitsSection = sec.name.toLowerCase().includes(q);
            const binds = hitsSection ? sec.binds : sec.binds.filter(b => b.key.toLowerCase().includes(q) || b.desc.toLowerCase().includes(q));
            if (binds.length > 0)
                out.push({
                    name: sec.name,
                    binds: binds
                });
        }
        return out;
    }

    readonly property int matchCount: root.filtered.reduce((n, s) => n + s.binds.length, 0)

    Process {
        id: proc
        command: [Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/keybinds"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.sections = JSON.parse(text).sections ?? [];
                } catch (e) {
                    root.sections = [];
                }
            }
        }
    }

    // Deal the sections into three balanced columns.
    readonly property var columns: {
        const cols = [[], [], []];
        const weights = [0, 0, 0];
        for (const s of root.filtered) {
            let target = 0;
            for (let i = 1; i < 3; i++)
                if (weights[i] < weights[target])
                    target = i;
            cols[target].push(s);
            weights[target] += s.binds.length + 2;
        }
        return cols;
    }

    Card {
        width: Math.min(root.width - Theme.spacingXL * 2, 1180)
        height: Math.min(root.height - Theme.spacingXL * 2, layout.implicitHeight + Theme.spacingXL * 2)

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingXL
            spacing: Theme.spacingL

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingL

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                    font.bold: true
                    color: Theme.textPrimary
                    text: "Keybinds"
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: Theme.accent
                    text: "󰍉"
                }

                TextInput {
                    id: search

                    Layout.fillWidth: true
                    focus: true

                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    color: Theme.textPrimary
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.textPrimary
                    clip: true

                    Keys.onEscapePressed: {
                        if (search.text !== "")
                            search.text = "";
                        else
                            Panels.close();
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        font: search.font
                        color: Theme.textDim
                        text: "Filter by key or action…"
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                    text: search.text === "" ? "from hypr/hyprland.lua · Esc to close" : root.matchCount + " match" + (root.matchCount === 1 ? "" : "es")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXL
                Layout.bottomMargin: Theme.spacingXL
                visible: root.matchCount === 0
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textDim
                text: "No keybind matches \"" + search.text + "\""
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.matchCount > 0
                spacing: Theme.spacingXL

                Repeater {
                    model: root.columns

                    ColumnLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.spacingL

                        Repeater {
                            model: parent.modelData

                            ColumnLayout {
                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    font.bold: true
                                    color: Theme.accent
                                    text: parent.modelData.name.toUpperCase()
                                }

                                Repeater {
                                    model: parent.modelData.binds

                                    RowLayout {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        spacing: Theme.spacingM

                                        Rectangle {
                                            implicitWidth: keyLabel.implicitWidth + 12
                                            implicitHeight: 20
                                            radius: 5
                                            color: Theme.hoverBg
                                            border.width: 1
                                            border.color: Theme.pillBorder

                                            Text {
                                                id: keyLabel
                                                anchors.centerIn: parent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize - 2
                                                color: Theme.textPrimary
                                                text: parent.parent.modelData.key
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                            color: Theme.textSecondary
                                            elide: Text.ElideRight
                                            text: parent.modelData.desc
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
