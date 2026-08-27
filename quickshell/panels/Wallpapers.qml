import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Wallpaper picker. Thumbnails come straight off disk; applying one shells
// out to scripts/wallpaper so the choice is persisted too.
Overlay {
    id: root

    panelName: "wallpapers"

    property var files: []
    property string current: ""

    // The "add a wallpaper" prompt, opened with n.
    property bool adding: false
    property string status: ""
    property bool busy: false

    readonly property string script: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/wallpaper"
    readonly property string addScript: Quickshell.env("HOME") + "/dotfiles/quickshell/scripts/wallpaper-add"

    onShownChanged: {
        if (shown) {
            root.adding = false;
            root.status = "";
            listProc.running = true;
            currentProc.running = true;
            grid.forceActiveFocus();
        }
    }

    Process {
        id: listProc
        command: [root.script, "--list"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.files = text.split("\n").filter(l => l !== "");
                // Keep the cursor on the wallpaper that is actually applied.
                const i = root.files.indexOf(root.current);
                if (i >= 0)
                    grid.currentIndex = i;
            }
        }
    }

    Process {
        id: currentProc
        command: [root.script]

        stdout: StdioCollector {
            onStreamFinished: {
                root.current = text.trim();
                const i = root.files.indexOf(root.current);
                if (i >= 0)
                    grid.currentIndex = i;
            }
        }
    }

    Process {
        id: applyProc
        command: [root.script]

        stdout: StdioCollector {
            onStreamFinished: root.current = text.trim()
        }
    }

    // Import from a URL or a path, then select what was imported.
    Process {
        id: addProc

        property string imported: ""

        stdout: StdioCollector {
            onStreamFinished: addProc.imported = text.trim()
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.status = text.trim();
            }
        }

        onExited: code => {
            root.busy = false;
            if (code === 0 && addProc.imported !== "") {
                root.adding = false;
                root.status = "";
                addField.text = "";
                listProc.running = true;
                root.apply(addProc.imported);
                grid.forceActiveFocus();
            } else if (root.status === "") {
                root.status = "import failed";
            }
        }
    }

    function apply(path) {
        applyProc.command = [root.script, path];
        applyProc.running = true;
        root.current = path;
    }

    function submitAdd() {
        const src = addField.text.trim();
        if (src === "" || root.busy)
            return;
        root.status = "importing…";
        root.busy = true;
        addProc.imported = "";
        addProc.command = [root.addScript, src];
        addProc.running = true;
    }

    function startAdding() {
        root.adding = true;
        root.status = "";
        addField.text = "";
        addField.forceActiveFocus();
    }

    function cancelAdding() {
        root.adding = false;
        root.status = "";
        grid.forceActiveFocus();
    }

    function displayName(path) {
        const base = path.split("/").pop().replace(/\.(png|jpe?g|webp)$/i, "");
        return base.charAt(0).toUpperCase() + base.slice(1);
    }

    Card {
        width: Math.min(root.width - Theme.spacingXL * 2, 1000)
        height: layout.implicitHeight + Theme.spacingXL * 2

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingXL
            spacing: Theme.spacingL

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                    font.bold: true
                    color: Theme.textPrimary
                    text: "Wallpaper"
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                    text: root.files.length + " available"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            // ── Add prompt ───────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: root.adding
                implicitHeight: 42
                radius: 8
                color: Theme.hoverBg
                border.width: 1
                border.color: Theme.alpha(Theme.accent, 0.4)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingM

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        color: Theme.accent
                        text: "󰋺"
                    }

                    TextInput {
                        id: addField

                        Layout.fillWidth: true
                        enabled: !root.busy

                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        color: Theme.textPrimary
                        selectionColor: Theme.alpha(Theme.accent, 0.35)
                        selectedTextColor: Theme.textPrimary
                        clip: true

                        onAccepted: root.submitAdd()
                        Keys.onEscapePressed: root.cancelAdding()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: addField.text === ""
                            font: addField.font
                            color: Theme.textDim
                            text: "Paste an image URL, or a path like ~/Pictures/shot.png"
                        }
                    }

                    Text {
                        visible: root.status !== ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: root.busy ? Theme.textDim : Theme.red
                        elide: Text.ElideRight
                        Layout.maximumWidth: 340
                        text: root.status
                    }

                    TextButton {
                        label: root.busy ? "Working" : "Add"
                        accented: true
                        onClicked: root.submitAdd()
                    }
                }
            }

            // ── Grid ─────────────────────────────────────────────
            GridView {
                id: grid

                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, 560)

                clip: true
                focus: !root.adding
                activeFocusOnTab: true
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 300)))
                cellHeight: cellWidth * 9 / 16 + 30
                boundsBehavior: Flickable.StopAtBounds
                model: root.files

                keyNavigationEnabled: true
                keyNavigationWraps: true

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_H:
                        grid.moveCurrentIndexLeft();
                        break;
                    case Qt.Key_L:
                        grid.moveCurrentIndexRight();
                        break;
                    case Qt.Key_J:
                        grid.moveCurrentIndexDown();
                        break;
                    case Qt.Key_K:
                        grid.moveCurrentIndexUp();
                        break;
                    case Qt.Key_N:
                        root.startAdding();
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        if (grid.currentIndex >= 0)
                            root.apply(root.files[grid.currentIndex]);
                        break;
                    // A focused GridView does not pass Escape up to the
                    // overlay's FocusScope, so close from here.
                    case Qt.Key_Escape:
                        Panels.close();
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index

                    readonly property bool isCurrent: modelData === root.current
                    readonly property bool isCursor: grid.currentIndex === cell.index

                    width: grid.cellWidth
                    height: grid.cellHeight

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: 4

                        ClippingRectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: Theme.raised
                            border.width: cell.isCurrent || cell.isCursor ? 2 : 1
                            border.color: cell.isCurrent ? Theme.accent : cell.isCursor ? Theme.alpha(Theme.accent, 0.55) : Theme.pillBorder

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: Theme.durFast
                                }
                            }

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                // Decode at display size; these are full-resolution files.
                                sourceSize.width: 480
                                source: "file://" + cell.modelData
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.alpha(Theme.accent, 0.18)
                                visible: (mouse.containsMouse || cell.isCursor) && !cell.isCurrent
                            }

                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: grid.currentIndex = cell.index
                                onClicked: root.apply(cell.modelData)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: cell.isCurrent ? Theme.accent : cell.isCursor ? Theme.textSecondary : Theme.textDim
                                elide: Text.ElideRight
                                text: root.displayName(cell.modelData)
                            }

                            Text {
                                visible: cell.isCurrent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.accent
                                text: "󰄬"
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
                text: root.adding ? "Enter to import · Esc to cancel" : "↑↓←→ or hjkl to move · Enter to apply · n to add · Esc to close"
            }
        }
    }
}
