import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    default property alias content: layout.data
    property int horizontalPadding: 10

    implicitWidth: layout.implicitWidth + horizontalPadding * 2
    visible: layout.implicitWidth > 0

    color: Theme.pillBg
    border.color: Theme.pillBorder
    border.width: 1
    radius: Theme.radius

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.leftMargin: parent.horizontalPadding
        anchors.rightMargin: parent.horizontalPadding
        spacing: 0
    }
}
