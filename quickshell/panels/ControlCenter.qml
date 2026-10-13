import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
import "../desktop"

// Audio mixer, media controls and session actions.
// Replaces the rofi audio_mixer_menu / cycle_sink scripts.
Overlay {
    id: root

    panelName: "control"
    contentAlign: Qt.AlignTop | Qt.AlignRight
    blurBackdrop: false

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    // First-seen order, same as the desktop media stack, so every player
    // shows up here rather than just whichever one is playing — except that
    // YouTube Music is pinned to the front, so the carousel always leads with it.
    readonly property var players: {
        const all = MediaOrder.players;
        const music = all.filter(p => root.isMusic(p));
        return music.concat(all.filter(p => !music.includes(p)));
    }
    // Streams already surfaced as a media card (e.g. the Chrome tab behind a
    // player) get their own transport + volume there, so drop them here to
    // avoid showing the same app's volume slider twice.
    readonly property var playerStreams: root.players.map(p => AudioLink.streamFor(p)).filter(s => s !== null)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio && n.type === PwNodeType.AudioOutStream && !root.playerStreams.includes(n))
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && n.type === PwNodeType.AudioSource)

    // Which player the media carousel is showing.
    property int mediaIndex: 0

    // YouTube Music runs in its own Chrome process (scripts/ytmusic), so its
    // player is the one whose window carries the app class Chrome derives.
    function isMusic(player) {
        const cls = String(WindowLink.windowFor(player)?.lastIpcObject?.["class"] ?? "");
        return cls.startsWith("chrome-music.youtube.com");
    }

    function stepMedia(delta) {
        const n = root.players.length;
        if (n > 0)
            root.mediaIndex = (Math.min(root.mediaIndex, n - 1) + delta + n) % n;
    }

    property bool showSinkPicker: false
    property bool showSourcePicker: false

    onShownChanged: {
        if (shown) {
            // Open on whatever is playing
            const playing = root.players.findIndex(p => p.isPlaying);
            if (playing >= 0)
                root.mediaIndex = playing;
        }
        if (!shown) {
            showSinkPicker = false;
            showSourcePicker = false;
        }
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.streams).concat(root.sinks).concat(root.sources)
    }

    function niceName(node) {
        return node.properties["application.name"] ?? node.nickname ?? node.description ?? node.name;
    }

    Component {
        id: nightSettings
        NightModeSettings {}
    }
    Component {
        id: networkSettings
        NetworkSettings {}
    }
    Component {
        id: bluetoothSettings
        BluetoothSettings {}
    }
    Component {
        id: focusSettings
        FocusSettings {}
    }

    // Both cards share one overlay, backdrop, and keyboard focus owner.
    Item {
        readonly property bool sideBySide: root.width >= controlCard.width + settings.width + Theme.spacingL +
                                                      (Theme.barMargin + Theme.barHeight + Theme.spacingM) * 2
        implicitWidth: controlCard.width + (settings.active && sideBySide ? settings.width + Theme.spacingL : 0)
        implicitHeight: Math.max(controlCard.height, settings.active ? settings.height : 0)

        Loader {
            id: settings
            active: Panels.settingsComponent !== null
            sourceComponent: Panels.settingsComponent
            focus: active
            width: item ? item.implicitWidth : 420
            height: item ? item.implicitHeight : 0
            x: parent.sideBySide ? 0 : (parent.width - width) / 2
            z: 1
        }

        Card {
            id: controlCard
            x: parent.width - width
            width: 420
            height: Math.min(root.height - Theme.barHeight - Theme.barMargin * 4, layout.implicitHeight + Theme.spacingL * 2)

            ColumnLayout {
                id: layout
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingL

                // ── Header ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 3
                        font.bold: true
                        color: Theme.textPrimary
                        text: "Control Center"
                    }

                    IconButton {
                        glyph: "󰐥"
                        glyphSize: Theme.fontSize + 2
                        hoverColor: Theme.red
                        onClicked: Panels.show("power")
                    }
                }

                // ── Output device ────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingM

                        IconButton {
                            glyph: root.sink?.audio?.muted ? "󰖁" : "󰕾"
                            glyphSize: 16
                            glyphColor: root.sink?.audio?.muted ? Theme.orange : Theme.textPrimary
                            onClicked: {
                                if (root.sink?.audio)
                                    root.sink.audio.muted = !root.sink.audio.muted;
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            text: root.sink?.description ?? "No output"
                        }

                        Text {
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textPrimary
                            text: Math.round((root.sink?.audio?.volume ?? 0) * 100) + "%"
                        }

                        IconButton {
                            glyph: root.showSinkPicker ? "󰅃" : "󰅀"
                            onClicked: root.showSinkPicker = !root.showSinkPicker
                        }
                    }

                    Slider {
                        Layout.fillWidth: true
                        value: root.sink?.audio?.volume ?? 0
                        fillColor: root.sink?.audio?.muted ? Theme.gray : Theme.accent
                        onMoved: v => {
                            if (root.sink?.audio)
                                root.sink.audio.volume = v;
                        }
                    }

                    // Output picker
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingS
                        visible: root.showSinkPicker
                        spacing: 2

                        Repeater {
                            model: root.sinks

                            MouseArea {
                                id: sinkRow
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 30
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    Pipewire.preferredDefaultAudioSink = modelData;
                                    root.showSinkPicker = false;
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: sinkRow.containsMouse ? Theme.hoverBg : "transparent"
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingS

                                    Text {
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                        color: sinkRow.modelData === root.sink ? Theme.accent : Theme.textDim
                                        text: sinkRow.modelData === root.sink ? "󰄬" : "󰧞"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                        color: sinkRow.modelData === root.sink ? Theme.textPrimary : Theme.textSecondary
                                        elide: Text.ElideRight
                                        text: sinkRow.modelData.description
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.separator
                }

                // ── Input device ─────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingM

                        IconButton {
                            glyph: root.source?.audio?.muted ? "󰍭" : "󰍬"
                            glyphSize: 16
                            glyphColor: root.source?.audio?.muted ? Theme.orange : Theme.textPrimary
                            onClicked: {
                                if (root.source?.audio)
                                    root.source.audio.muted = !root.source.audio.muted;
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            text: root.source?.description ?? "No input"
                        }

                        Text {
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textPrimary
                            text: Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"
                        }

                        IconButton {
                            glyph: root.showSourcePicker ? "󰅃" : "󰅀"
                            onClicked: root.showSourcePicker = !root.showSourcePicker
                        }
                    }

                    Slider {
                        Layout.fillWidth: true
                        value: root.source?.audio?.volume ?? 0
                        fillColor: root.source?.audio?.muted ? Theme.gray : Theme.accent
                        onMoved: v => {
                            if (root.source?.audio)
                                root.source.audio.volume = v;
                        }
                    }

                    // Input picker
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingS
                        visible: root.showSourcePicker
                        spacing: 2

                        Repeater {
                            model: root.sources

                            MouseArea {
                                id: sourceRow
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 30
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    Pipewire.preferredDefaultAudioSource = modelData;
                                    root.showSourcePicker = false;
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: sourceRow.containsMouse ? Theme.hoverBg : "transparent"
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingS

                                    Text {
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                        color: sourceRow.modelData === root.source ? Theme.accent : Theme.textDim
                                        text: sourceRow.modelData === root.source ? "󰄬" : "󰧞"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                        color: sourceRow.modelData === root.source ? Theme.textPrimary : Theme.textSecondary
                                        elide: Text.ElideRight
                                        text: sourceRow.modelData.description
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.separator
                    visible: root.streams.length > 0
                }

                // ── Per-app volume ───────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    visible: root.streams.length > 0

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.textDim
                        text: "APPLICATIONS"
                    }

                    Repeater {
                        model: root.streams

                        ColumnLayout {
                            id: streamRow
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 2

                            PwNodePeakMonitor {
                                id: peak
                                node: streamRow.modelData
                                enabled: root.shown
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

                                IconButton {
                                    glyph: streamRow.modelData.audio.muted ? "󰝟" : "󰕾"
                                    glyphSize: 13
                                    glyphColor: streamRow.modelData.audio.muted ? Theme.orange : Theme.textSecondary
                                    onClicked: streamRow.modelData.audio.muted = !streamRow.modelData.audio.muted
                                }

                                Text {
                                    Layout.fillWidth: true
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                    text: root.niceName(streamRow.modelData)
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    color: Theme.textDim
                                    text: Math.round(streamRow.modelData.audio.volume * 100) + "%"
                                }
                            }

                            Slider {
                                Layout.fillWidth: true
                                value: streamRow.modelData.audio.volume
                                level: peak.peak
                                showLevel: true
                                fillColor: streamRow.modelData.audio.muted ? Theme.gray : Theme.accent
                                onMoved: v => streamRow.modelData.audio.volume = v
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.separator
                    visible: root.players.length > 0
                }

                // ── Media ────────────────────────────────────────────
                // Same MediaCard used on the desktop widget stack, and the same
                // first-seen ordering (music first), but one player at a time: the pager
                // below steps between them instead of stacking every card.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    visible: root.players.length > 0

                    ListView {
                        id: mediaCarousel
                        Layout.fillWidth: true
                        Layout.preferredHeight: currentItem?.implicitHeight ?? 0
                        orientation: ListView.Horizontal
                        snapMode: ListView.SnapOneItem
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        highlightMoveDuration: Theme.durMed
                        // Dragging would fight the seek and volume sliders
                        interactive: false
                        clip: true
                        spacing: Theme.spacingL
                        model: root.players
                        currentIndex: Math.max(0, Math.min(root.mediaIndex, count - 1))

                        delegate: MediaCard {
                            required property var modelData
                            width: ListView.view.width
                            player: modelData
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.spacingS
                        visible: root.players.length > 1

                        IconButton {
                            glyph: "󰅁"
                            onClicked: root.stepMedia(-1)
                        }

                        Repeater {
                            model: root.players.length

                            MouseArea {
                                id: dot
                                required property int index

                                implicitWidth: 12
                                implicitHeight: 12
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.mediaIndex = index

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: dot.index === mediaCarousel.currentIndex ? Theme.accent : Theme.textDim
                                }
                            }
                        }

                        IconButton {
                            glyph: "󰅂"
                            onClicked: root.stepMedia(1)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.separator
                }

                // Four square options per row; details use the shared pane.
                GridLayout {
                    id: optionGrid
                    readonly property int tileSize: Math.round((controlCard.width - Theme.spacingL * 2 - Theme.spacingS * 3) / 4 * 0.85)
                    readonly property real tileGap: (controlCard.width - tileSize * 4) / 5
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 0
                    Layout.bottomMargin: tileGap - Theme.spacingL
                    columns: 4
                    columnSpacing: tileGap
                    rowSpacing: tileGap

                    NetworkCard {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.minimumWidth: optionGrid.tileSize
                        Layout.maximumWidth: optionGrid.tileSize
                        Layout.preferredWidth: optionGrid.tileSize
                        Layout.preferredHeight: width
                        settingsComponent: networkSettings
                    }
                    BluetoothCard {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.minimumWidth: optionGrid.tileSize
                        Layout.maximumWidth: optionGrid.tileSize
                        Layout.preferredWidth: optionGrid.tileSize
                        Layout.preferredHeight: width
                        settingsComponent: bluetoothSettings
                    }
                    NightModeCard {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.minimumWidth: optionGrid.tileSize
                        Layout.maximumWidth: optionGrid.tileSize
                        Layout.preferredWidth: optionGrid.tileSize
                        Layout.preferredHeight: width
                        settingsComponent: nightSettings
                        active: root.shown
                    }
                    FocusCard {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.minimumWidth: optionGrid.tileSize
                        Layout.maximumWidth: optionGrid.tileSize
                        Layout.preferredWidth: optionGrid.tileSize
                        Layout.preferredHeight: width
                        settingsComponent: focusSettings
                    }
                }

                // ── Quick toggles ────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    TextButton {
                        Layout.alignment: Qt.AlignTop
                        label: "󰅌  Clipboard"
                        onClicked: Panels.show("clipboard")
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    TextButton {
                        Layout.alignment: Qt.AlignTop
                        label: "󰌾  Lock"
                        onClicked: {
                            Panels.close();
                            Quickshell.execDetached(["hyprlock"]);
                        }
                    }
                }
            }
        }
    }
}
