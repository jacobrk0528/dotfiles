import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// One MPRIS player: artwork, metadata, seek bar, transport and volume.
ColumnLayout {
    id: root

    required property MprisPlayer player

    // Chrome ignores MPRIS volume, so drive the player's PipeWire stream
    // instead and fall back to MPRIS only when there is no stream to find.
    readonly property PwNode stream: AudioLink.streamFor(root.player)
    readonly property bool hasVolume: stream !== null || (player?.volumeSupported ?? false)
    readonly property real volume: stream?.audio?.volume ?? player?.volume ?? 0
    readonly property bool muted: stream?.audio?.muted ?? false

    function setVolume(v) {
        if (root.stream?.audio)
            root.stream.audio.volume = v;
        else if (root.player?.volumeSupported)
            root.player.volume = v;
    }

    function toggleMute() {
        if (root.stream?.audio)
            root.stream.audio.muted = !root.stream.audio.muted;
    }

    spacing: Theme.spacingS

    PwObjectTracker {
        objects: root.stream ? [root.stream] : []
    }

    function fmt(seconds) {
        if (!seconds || seconds < 0)
            return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // Position only ticks while playing; MPRIS does not push updates.
    Timer {
        interval: 1000
        running: root.player?.isPlaying ?? false
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    // Artwork and metadata double as the handle for the player's window.
    MouseArea {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: WindowLink.focus(root.player)

        RowLayout {
            id: header

            anchors.fill: parent
            spacing: Theme.spacingM

            ClippingRectangle {
                implicitWidth: 52
                implicitHeight: 52
                radius: 8
                color: Theme.alpha("#ffffff", 0.08)

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: root.player?.trackArtUrl ?? ""
                }

                Text {
                    anchors.centerIn: parent
                    visible: !root.player?.trackArtUrl
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    color: Theme.textDim
                    text: "󰎈"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.alpha("#ffffff", 0.9)
                    elide: Text.ElideRight
                    text: root.player?.trackTitle ?? ""
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.alpha("#ffffff", 0.55)
                    elide: Text.ElideRight
                    text: root.player?.trackArtist ?? ""
                }

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    color: Theme.accent
                    elide: Text.ElideRight
                    text: root.player?.identity ?? ""
                }
            }
        }
    }

    // ── Seek ─────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: root.player?.lengthSupported ?? false
        spacing: Theme.spacingS

        Text {
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            color: Theme.alpha("#ffffff", 0.45)
            text: root.fmt(root.player?.position ?? 0)
        }

        Slider {
            Layout.fillWidth: true
            implicitHeight: 12
            value: {
                const len = root.player?.length ?? 0;
                return len > 0 ? (root.player.position / len) : 0;
            }
            fillColor: Theme.accent
            enabled: root.player?.canSeek ?? false
            opacity: enabled ? 1 : 0.5
            onMoved: v => {
                if (root.player?.canSeek && root.player.length > 0)
                    root.player.position = v * root.player.length;
            }
        }

        Text {
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            color: Theme.alpha("#ffffff", 0.45)
            text: root.fmt(root.player?.length ?? 0)
        }
    }

    // ── Transport + volume ───────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingS

        IconButton {
            glyph: "󰒮"
            size: 24
            enabled: root.player?.canGoPrevious ?? false
            opacity: enabled ? 1 : 0.3
            onClicked: root.player.previous()
        }

        IconButton {
            glyph: root.player?.isPlaying ? "󰏤" : "󰐊"
            size: 24
            glyphSize: Theme.fontSize + 3
            glyphColor: Theme.accent
            enabled: root.player?.canTogglePlaying ?? false
            opacity: enabled ? 1 : 0.3
            onClicked: root.player.togglePlaying()
        }

        IconButton {
            glyph: "󰒭"
            size: 24
            enabled: root.player?.canGoNext ?? false
            opacity: enabled ? 1 : 0.3
            onClicked: root.player.next()
        }

        Item {
            implicitWidth: Theme.spacingS
        }

        IconButton {
            visible: root.hasVolume
            glyph: root.muted ? "󰝟" : "󰕾"
            size: 20
            glyphSize: Theme.fontSize - 1
            glyphColor: root.muted ? Theme.orange : Theme.alpha("#ffffff", 0.5)
            onClicked: root.toggleMute()
        }

        Slider {
            Layout.fillWidth: true
            implicitHeight: 12
            visible: root.hasVolume
            value: root.volume
            fillColor: root.muted ? Theme.gray : Theme.alpha(Theme.accent, 0.8)
            onMoved: v => root.setVolume(v)
        }
    }
}
