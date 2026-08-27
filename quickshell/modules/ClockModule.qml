import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"

BarModule {
    id: root

    horizontalPadding: 0
    textColor: Theme.textPrimary
    text: Qt.formatDateTime(clock.date, "ddd MMM dd  HH:mm:ss")

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // Calendar popup (replaces waybar's calendar tooltip)
    onContainsMouseChanged: {
        if (containsMouse)
            calDelay.start();
        else {
            calDelay.stop();
            calPopup.visible = false;
        }
    }

    Timer {
        id: calDelay
        interval: 350
        onTriggered: calPopup.visible = root.containsMouse
    }

    PopupWindow {
        id: calPopup
        visible: false

        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 8

        implicitWidth: calColumn.implicitWidth + 36
        implicitHeight: calColumn.implicitHeight + 28
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Theme.tooltipBg
            border.color: Theme.tooltipBorder
            border.width: 1
            radius: 8

            ColumnLayout {
                id: calColumn
                anchors.centerIn: parent
                spacing: 6

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    color: Theme.pink
                    text: Qt.formatDate(clock.date, "MMMM yyyy")
                }

                DayOfWeekRow {
                    id: dow
                    Layout.fillWidth: true
                    locale: grid.locale

                    delegate: Text {
                        required property var model
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.orange
                        text: model.shortName
                    }
                }

                MonthGrid {
                    id: grid
                    Layout.fillWidth: true
                    month: clock.date.getMonth()
                    year: clock.date.getFullYear()

                    delegate: Text {
                        required property var model
                        horizontalAlignment: Text.AlignHCenter
                        padding: 4
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: model.today
                        font.underline: model.today
                        color: model.today ? Theme.red
                             : model.month === grid.month ? Theme.green
                             : Theme.textDim
                        text: model.day
                    }
                }
            }
        }
    }
}
