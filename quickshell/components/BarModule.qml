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
    implicitWidth: label.implicitWidth + horizontalPadding * 2

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
        anchors.centerIn: parent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: root.textColor
        text: root.displayText
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
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 8

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
