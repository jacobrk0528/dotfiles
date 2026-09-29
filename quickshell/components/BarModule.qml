import Quickshell
import QtQuick
import ".."

// Base for all bar modules: icon + text display, hover tooltip, click/scroll signals.
MouseArea {
    id: root

    property var bar
    property string icon: ""
    property string text: ""
    property string tooltipText: "" // Qt rich text (use Theme.pangoToRichText for script output)
    property color textColor: Theme.textSecondary
    property int horizontalPadding: 8
    property int fontSize: Theme.fontSize
    // Open the tooltip above the module instead of below (bottom dock)
    property bool tooltipAbove: false
    // Set to render as a scorecard: small title over icon + value
    property string title: ""
    readonly property bool card: title !== ""
    // [warn, crit]: colour the card's value green / yellow / red by the
    // first number in text (e.g. "62°C" → 62)
    property var thresholds: null

    readonly property color valueColor: {
        const m = root.thresholds ? String(root.text).match(/-?\d+(\.\d+)?/) : null;
        if (!m)
            return Theme.textPrimary;
        const v = parseFloat(m[0]);
        return v >= root.thresholds[1] ? Theme.red : v >= root.thresholds[0] ? Theme.yellow : Theme.green;
    }

    signal leftClicked
    signal rightClicked
    signal middleClicked
    signal scrolled(int delta)

    // Modules with nothing to report collapse; set alwaysVisible to keep
    // showing the icon alone (status indicators like the notification bell).
    property bool alwaysVisible: false

    readonly property string displayText: {
        if (!root.text)
            return root.alwaysVisible ? root.icon : "";
        return root.icon ? root.icon + " " + root.text : root.text;
    }

    visible: displayText !== ""
    implicitWidth: card ? Math.max(cardColumn.implicitWidth + 24, 76) : label.implicitWidth + horizontalPadding * 2

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton)
            root.leftClicked();
        else if (mouse.button === Qt.RightButton)
            root.rightClicked();
        else if (mouse.button === Qt.MiddleButton)
            root.middleClicked();
    }

    onWheel: wheel => root.scrolled(wheel.angleDelta.y)

    Text {
        id: label
        visible: !root.card
        anchors.centerIn: parent
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: root.textColor
        text: root.displayText
    }

    Rectangle {
        visible: root.card
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.radius
        color: root.containsMouse ? Theme.activeBg : Theme.hoverBg

        Behavior on color {
            ColorAnimation { duration: Theme.durFast }
        }

        Column {
            id: cardColumn
            anchors.centerIn: parent
            spacing: 2

            Text {
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.letterSpacing: 0.5
                color: Theme.textDim
                text: root.title.toUpperCase()
            }

            Row {
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textSecondary
                    text: root.icon
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    color: root.valueColor
                    text: root.text

                    Behavior on color {
                        ColorAnimation { duration: Theme.durMed }
                    }
                }
            }
        }
    }

    onContainsMouseChanged: {
        if (containsMouse && root.tooltipText !== "")
            tipDelay.start();
        else {
            tipDelay.stop();
            tip.visible = false;
        }
    }

    Timer {
        id: tipDelay
        interval: 350
        onTriggered: tip.visible = root.containsMouse && root.tooltipText !== ""
    }

    PopupWindow {
        id: tip
        visible: false

        anchor.item: root
        anchor.edges: root.tooltipAbove ? Edges.Top : Edges.Bottom
        anchor.gravity: root.tooltipAbove ? Edges.Top : Edges.Bottom
        anchor.margins.top: root.tooltipAbove ? -8 : 8

        implicitWidth: tipLabel.implicitWidth + 28
        implicitHeight: tipLabel.implicitHeight + 20
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Theme.tooltipBg
            border.color: Theme.tooltipBorder
            border.width: 1
            radius: 8

            Text {
                id: tipLabel
                anchors.centerIn: parent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tooltipFontSize
                color: Theme.textPrimary
                textFormat: Text.StyledText
                text: root.tooltipText
            }
        }
    }
}
