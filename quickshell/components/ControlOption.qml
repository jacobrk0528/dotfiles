import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// Left-click performs the option's action; right-click opens its settings.
MouseArea {
    id: root
    property string label: ""
    property string glyph: ""
    property string subtitle: ""
    property bool accented: false
    property color accentColor: Theme.accent
    property Component settingsComponent: null
    signal activated()
    implicitWidth: 108
    implicitHeight: 108
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (settingsComponent !== null)
                Panels.showSettings(settingsComponent);
        } else {
            activated();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.pressed ? Theme.pressedBg : root.accented ? Theme.alpha(root.accentColor, root.containsMouse ? 0.2 : 0.12)
                                                                              : root.containsMouse ? Theme.activeBg : Theme.hoverBg
        border.color: root.accented ? Theme.alpha(root.accentColor, 0.35) : Theme.pillBorder
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: 4
        Item { Layout.fillHeight: true }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.glyph
            font.family: Theme.fontFamily
            font.pixelSize: 24
            color: root.accented ? root.accentColor : Theme.textSecondary
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            color: Theme.textPrimary
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.subtitle
            elide: Text.ElideRight
            visible: text !== ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            color: Theme.textDim
        }
        Item { Layout.fillHeight: true }
    }
}
