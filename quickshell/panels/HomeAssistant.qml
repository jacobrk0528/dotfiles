import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Quick light/media control: all lights, or by group. State and control
// both live in services/HALights.qml (shared with the always-on desktop
// widget). Whichever button (On/Off) matches the group's current state
// lights up yellow.
//
// Keyboard: j/k move the selection down/up between rows, h/l step left/right
// between columns (On, Off, and — for light rows only — the color swatch),
// Enter activates whatever is selected (On/Off toggles the group, the
// swatch opens/closes its color wheel). No letter mnemonics (k for
// kitchen, etc.) — those collide with j/k/h/l navigation, and with only a
// handful of rows a mnemonic saves at most one keypress anyway.
Overlay {
    id: root

    panelName: "homeassistant"

    property int selectedRow: 0
    property int selectedCol: 0 // 0 = On, 1 = Off, 2 = color swatch (light rows only)

    // Which group's color wheel is expanded, "" = none.
    property string colorPickerGroup: ""

    function columnCount(rowIndex) {
        return HALights.groups[rowIndex].section === "Lights" ? 3 : 2;
    }

    function activate() {
        const group = HALights.groups[root.selectedRow].group;
        if (root.selectedCol === 2)
            root.colorPickerGroup = root.colorPickerGroup === group ? "" : group;
        else
            HALights.run(root.selectedCol === 0 ? "on" : "off", group);
    }

    onShownChanged: {
        if (shown) {
            selectedRow = 0;
            selectedCol = 0;
            colorPickerGroup = "";
            HALights.refresh();
            keys.forceActiveFocus();
        }
    }

    FocusScope {
        id: keys
        width: card.width
        height: card.height
        focus: root.shown

        Keys.onPressed: event => {
            if (event.key === Qt.Key_J) {
                root.selectedRow = (root.selectedRow + 1) % HALights.groups.length;
                root.selectedCol = Math.min(root.selectedCol, root.columnCount(root.selectedRow) - 1);
            } else if (event.key === Qt.Key_K) {
                root.selectedRow = (root.selectedRow + HALights.groups.length - 1) % HALights.groups.length;
                root.selectedCol = Math.min(root.selectedCol, root.columnCount(root.selectedRow) - 1);
            } else if (event.key === Qt.Key_H) {
                root.selectedCol = Math.max(0, root.selectedCol - 1);
            } else if (event.key === Qt.Key_L) {
                root.selectedCol = Math.min(root.columnCount(root.selectedRow) - 1, root.selectedCol + 1);
            } else {
                return;
            }
            event.accepted = true;
        }
        Keys.onReturnPressed: root.activate()
        Keys.onEnterPressed: root.activate()

        Card {
            id: card
            width: 320
            height: layout.implicitHeight + Theme.spacingL * 2

            ColumnLayout {
                id: layout
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingL

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                    color: Theme.textPrimary
                    text: "Home"
                }

                Repeater {
                    model: HALights.groups

                    ColumnLayout {
                        id: rowDelegate
                        required property var modelData
                        required property int index

                        // Not named "state" — that's a built-in Item
                        // property used by QML's State/Transition system.
                        readonly property string lightState: HALights.groupStates[modelData.group] ?? ""
                        readonly property bool isNewSection: index === 0 || HALights.groups[index - 1].section !== modelData.section

                        Layout.fillWidth: true
                        spacing: Theme.spacingS

                        Text {
                            visible: rowDelegate.isNewSection
                            Layout.fillWidth: true
                            Layout.topMargin: rowDelegate.index === 0 ? 0 : Theme.spacingS
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                            color: Theme.textDim
                            text: modelData.section
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM

                            Text {
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.textSecondary
                                text: rowDelegate.modelData.label
                            }

                            TextButton {
                                label: "On"
                                accented: rowDelegate.lightState === "on"
                                accentColor: Theme.yellow
                                current: root.selectedRow === rowDelegate.index && root.selectedCol === 0
                                onClicked: HALights.run("on", rowDelegate.modelData.group)
                            }

                            TextButton {
                                label: "Off"
                                accented: rowDelegate.lightState === "off"
                                accentColor: Theme.yellow
                                current: root.selectedRow === rowDelegate.index && root.selectedCol === 1
                                onClicked: HALights.run("off", rowDelegate.modelData.group)
                            }

                            // Color wheel toggle — lights only, TV has no color.
                            // Plain gradient swatch rather than a tiny
                            // Canvas instance — simpler and guaranteed to
                            // render at icon size.
                            Rectangle {
                                visible: rowDelegate.modelData.section === "Lights"
                                implicitWidth: 20
                                implicitHeight: 20
                                radius: 10
                                border.width: root.selectedRow === rowDelegate.index && root.selectedCol === 2 ? 2 : 1
                                border.color: root.selectedRow === rowDelegate.index && root.selectedCol === 2 ? Theme.textPrimary : Theme.pillBorder

                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.red }
                                    GradientStop { position: 0.5; color: Theme.yellow }
                                    GradientStop { position: 1.0; color: Theme.accent }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.colorPickerGroup = root.colorPickerGroup === rowDelegate.modelData.group ? "" : rowDelegate.modelData.group
                                }
                            }
                        }

                        ColorWheel {
                            visible: root.colorPickerGroup === rowDelegate.modelData.group
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Theme.spacingS
                            Layout.bottomMargin: Theme.spacingS
                            diameter: 140
                            onColorPicked: (r, g, b) => HALights.setColor(rowDelegate.modelData.group, r, g, b)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    color: Theme.textDim
                    text: "hjkl to move · Enter to select"
                }
            }
        }
    }
}
