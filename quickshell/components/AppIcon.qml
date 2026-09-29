import Quickshell.Widgets
import QtQuick
import ".."

// An app's icon, or — when the icon theme has nothing for it — a rounded
// tile with its initial, tinted from the palette by name so each app keeps
// the same colour.
Item {
    id: root

    property string source: ""
    property string name: ""
    property int size: 48

    implicitWidth: size
    implicitHeight: size

    readonly property color tint: {
        const palette = [Theme.accent, Theme.green, Theme.yellow, Theme.pink, Theme.orange, Theme.purple];
        let h = 0;
        for (let i = 0; i < root.name.length; i++)
            h = (h * 31 + root.name.charCodeAt(i)) >>> 0;
        return palette[h % palette.length];
    }

    IconImage {
        id: image
        anchors.fill: parent
        implicitSize: root.size
        source: root.source
        visible: root.source !== "" && status !== Image.Error
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.size * 0.06
        visible: !image.visible
        radius: width * 0.28
        color: Theme.alpha(root.tint, 0.18)
        border.width: 1
        border.color: Theme.alpha(root.tint, 0.35)

        Text {
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: parent.height * 0.5
            font.bold: true
            color: root.tint
            text: (root.name.trim()[0] ?? "?").toUpperCase()
        }
    }
}
