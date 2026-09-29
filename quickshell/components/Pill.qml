import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    default property alias content: layout.data
    property int horizontalPadding: 10
    property alias spacing: layout.spacing

    implicitWidth: layout.implicitWidth + horizontalPadding * 2
    visible: layout.implicitWidth > 0

    // Bare: the bar's own BarSurface is the background
    color: "transparent"

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.leftMargin: parent.horizontalPadding
        anchors.rightMargin: parent.horizontalPadding
        spacing: 0
    }
}
