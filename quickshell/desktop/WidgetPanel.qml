import QtQuick
import QtQuick.Layouts
import ".."

// Translucent rounded backing for a desktop widget, so its text stays
// readable over a light wallpaper without dimming the whole screen.
Rectangle {
    id: root

    default property alias content: layout.data
    property int padding: Theme.spacingL
    property alias spacing: layout.spacing

    implicitWidth: layout.implicitWidth + padding * 2
    implicitHeight: layout.implicitHeight + padding * 2

    color: Theme.widgetBg
    border.color: Theme.widgetBorder
    border.width: 1
    radius: Theme.panelRadius

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: Theme.spacingM
    }
}
