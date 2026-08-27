import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"

// One PipeWire playback stream: independent volume, mute and a live level
// meter. Chrome labels every tab's stream identically, so the meter is what
// tells them apart — the one that's moving is the one making noise.
ColumnLayout {
    id: root

    required property PwNode node
    // Disambiguates identically-named streams from the same app.
    property int ordinal: 0
    property int total: 1

    spacing: 1

    readonly property string label: {
        const props = root.node.properties;
        const app = props["application.name"] ?? root.node.nickname ?? root.node.description ?? root.node.name;
        const media = props["media.name"] ?? "";
        // "Playback" is Chrome's placeholder and tells you nothing.
        if (media && media !== "Playback" && media !== app)
            return app + " · " + media;
        return root.total > 1 ? app + " " + (root.ordinal + 1) : app;
    }

    PwObjectTracker {
        objects: [root.node]
    }

    PwNodePeakMonitor {
        id: peak
        node: root.node
        enabled: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingS

        IconButton {
            glyph: root.node.audio?.muted ? "󰝟" : "󰕾"
            size: 20
            glyphSize: Theme.fontSize - 1
            glyphColor: root.node.audio?.muted ? Theme.orange : Theme.alpha("#ffffff", 0.55)
            onClicked: {
                if (root.node.audio)
                    root.node.audio.muted = !root.node.audio.muted;
            }
        }

        Text {
            Layout.fillWidth: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            color: Theme.alpha("#ffffff", 0.65)
            elide: Text.ElideRight
            text: root.label
        }

        Text {
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            color: Theme.alpha("#ffffff", 0.4)
            text: Math.round((root.node.audio?.volume ?? 0) * 100) + "%"
        }
    }

    Slider {
        Layout.fillWidth: true
        Layout.leftMargin: 26
        implicitHeight: 12
        value: root.node.audio?.volume ?? 0
        level: peak.peak
        showLevel: true
        fillColor: root.node.audio?.muted ? Theme.gray : Theme.accent
        onMoved: v => {
            if (root.node.audio)
                root.node.audio.volume = v;
        }
    }
}
