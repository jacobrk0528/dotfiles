import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import ".."

Item {
    id: root

    property var bar

    visible: SystemTray.items.values.length > 0
    implicitWidth: visible ? trayRow.implicitWidth + 16 : 0

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: SystemTray.items

            MouseArea {
                id: trayItem
                required property SystemTrayItem modelData

                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                IconImage {
                    anchors.fill: parent
                    source: trayItem.modelData.icon
                }

                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        if (trayItem.modelData.onlyMenu)
                            menuAnchor.open();
                        else
                            trayItem.modelData.activate();
                    } else if (mouse.button === Qt.RightButton) {
                        if (trayItem.modelData.hasMenu)
                            menuAnchor.open();
                    } else if (mouse.button === Qt.MiddleButton) {
                        trayItem.modelData.secondaryActivate();
                    }
                }

                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayItem.modelData.menu

                    anchor.item: trayItem
                    anchor.edges: Edges.Bottom
                    anchor.gravity: Edges.Bottom
                }
            }
        }
    }
}
