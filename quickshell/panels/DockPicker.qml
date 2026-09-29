import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// "Add to Dock" — opened by right-clicking empty space on the dock. A grid of
// every installed app; click (or Enter) toggles its pin, and pinned apps wear
// a check. Stays open so several can be added in one go.
Overlay {
    id: root

    panelName: "dockpicker"

    onShownChanged: {
        if (shown) {
            search.text = "";
            grid.currentIndex = 0;
            search.forceActiveFocus();
        }
    }

    readonly property var entries: {
        const q = search.text.trim().toLowerCase();
        return DesktopEntries.applications.values
            .filter(e => !e.noDisplay && (q === "" || e.name.toLowerCase().includes(q)))
            .sort((a, b) => a.name.localeCompare(b.name));
    }

    function toggle(entry) {
        if (entry)
            DockApps.setPinned({ key: entry.id }, !DockApps.pins.includes(entry.id));
    }

    Card {
        width: 720
        height: layout.implicitHeight + Theme.spacingL * 2

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            // ── Header + search ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.accent
                    text: "󰐕"
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

                    onTextChanged: grid.currentIndex = 0

                    Keys.onRightPressed: grid.moveCurrentIndexRight()
                    Keys.onLeftPressed: grid.moveCurrentIndexLeft()
                    Keys.onDownPressed: grid.moveCurrentIndexDown()
                    Keys.onUpPressed: grid.moveCurrentIndexUp()
                    Keys.onEscapePressed: Panels.close()
                    Keys.onReturnPressed: root.toggle(root.entries[grid.currentIndex])
                    Keys.onEnterPressed: root.toggle(root.entries[grid.currentIndex])

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        font: search.font
                        color: Theme.textDim
                        text: "Add to Dock…"
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                    text: DockApps.pins.length + " pinned"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            // ── App grid ─────────────────────────────────────────
            GridView {
                id: grid

                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, cellHeight * 4)
                visible: root.entries.length > 0

                clip: true
                cellWidth: Math.floor(width / 6)
                cellHeight: 104
                boundsBehavior: Flickable.StopAtBounds
                model: root.entries

                delegate: MouseArea {
                    id: cell

                    required property var modelData
                    required property int index
                    readonly property bool pinned: DockApps.pins.includes(modelData.id)
                    readonly property bool current: grid.currentIndex === index

                    width: grid.cellWidth
                    height: grid.cellHeight
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: grid.currentIndex = index
                    onClicked: root.toggle(modelData)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: Theme.radius
                        color: cell.current ? Theme.activeBg : "transparent"
                        border.width: cell.pinned ? 1 : 0
                        border.color: Theme.alpha(Theme.accent, 0.5)

                        Behavior on color {
                            ColorAnimation { duration: Theme.durFast }
                        }
                    }

                    AppIcon {
                        id: icon
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        size: 48
                        source: Quickshell.iconPath(cell.modelData.icon, true)
                        name: cell.modelData.name
                        scale: cell.current ? 1.06 : 1

                        Behavior on scale {
                            NumberAnimation { duration: Theme.durFast; easing.type: Theme.easing }
                        }
                    }

                    // Pinned check, top right of the icon
                    Rectangle {
                        visible: cell.pinned
                        anchors.right: icon.right
                        anchors.top: icon.top
                        anchors.rightMargin: -6
                        anchors.topMargin: -6
                        width: 18
                        height: 18
                        radius: 9
                        color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.base
                            text: "✓"
                        }
                    }

                    Text {
                        anchors.top: icon.bottom
                        anchors.topMargin: 8
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: cell.pinned ? Theme.textPrimary : Theme.textSecondary
                        text: cell.modelData.name
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

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
                text: "click or ↵ to pin / unpin · esc to close"
            }
        }
    }
}
