import Quickshell.Wayland
import QtQuick
import ".."

Item {
    id: root

    readonly property string title: ToplevelManager.activeToplevel?.title ?? ""
    readonly property string shortTitle: title.length > 35 ? title.slice(0, 34) + "…" : title

    visible: shortTitle !== ""
    implicitWidth: visible ? divider.width + titleText.implicitWidth + 18 : 0

    Rectangle {
        id: divider
        width: 1
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.leftMargin: 8
        color: Theme.pillBorder
    }

    Text {
        id: titleText
        anchors.left: divider.right
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 0.5
        color: Theme.wsHoverFg
        text: root.shortTitle
    }
}
