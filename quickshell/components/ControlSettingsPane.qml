import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// Shared settings chrome. The control center owns placement and focus.
Card {
    id: root
    required property string title
    default property alias content: body.data
    implicitWidth: 420
    implicitHeight: layout.implicitHeight + Theme.spacingL * 2
    width: implicitWidth
    height: implicitHeight

    // Consume clicks on empty space so they don't reach the overlay backdrop.
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingL

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 3
                font.bold: true
                color: Theme.textPrimary
            }
            IconButton {
                glyph: "󰅖"
                onClicked: Panels.closeSettings()
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Theme.spacingL
        }
    }
}
