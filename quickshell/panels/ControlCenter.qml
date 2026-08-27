import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Audio mixer, media controls and session actions.
// Replaces the rofi audio_mixer_menu / cycle_sink scripts.
Overlay {
    id: root

    panelName: "control"
    contentAlign: Qt.AlignTop | Qt.AlignRight

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio && n.type === PwNodeType.AudioOutStream)
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property MprisPlayer player: {
        const ps = MediaOrder.players;
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null;
    }

    property bool showSinkPicker: false

    onShownChanged: {
        if (!shown)
            showSinkPicker = false;
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink].concat(root.streams).concat(root.sinks)
    }

    function niceName(node) {
        return node.properties["application.name"] ?? node.nickname ?? node.description ?? node.name;
    }

    Card {
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
                visible: root.player !== null
            }

            // ── Media ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM
                visible: root.player !== null

                ClippingRectangle {
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 8
                    color: Theme.raised

                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: root.player?.trackArtUrl ?? ""
                        asynchronous: true
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
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        text: root.player?.trackTitle ?? ""
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.textDim
                        elide: Text.ElideRight
                        text: root.player?.trackArtist ?? ""
                    }

                    RowLayout {
                        Layout.topMargin: 2
                        spacing: Theme.spacingS

                        IconButton {
                            glyph: "󰒮"
                            size: 22
                            enabled: root.player?.canGoPrevious ?? false
                            opacity: enabled ? 1 : 0.35
                            onClicked: root.player.previous()
                        }

                        IconButton {
                            glyph: root.player?.isPlaying ? "󰏤" : "󰐊"
                            size: 22
                            glyphSize: Theme.fontSize + 2
                            glyphColor: Theme.accent
                            onClicked: root.player.togglePlaying()
                        }

                        IconButton {
                            glyph: "󰒭"
                            size: 22
                            enabled: root.player?.canGoNext ?? false
                            opacity: enabled ? 1 : 0.35
                            onClicked: root.player.next()
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            color: Theme.textDim
                            visible: root.player?.lengthSupported ?? false
                            text: {
                                const fmt = s => {
                                    const m = Math.floor(s / 60);
                                    const sec = Math.floor(s % 60);
                                    return m + ":" + (sec < 10 ? "0" : "") + sec;
                                };
                                if (!root.player)
                                    return "";
                                return fmt(root.player.position) + " / " + fmt(root.player.length);
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

            // ── Connectivity ─────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                NetworkSection {
                    Layout.fillWidth: true
                }

                BluetoothSection {
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            // ── Quick toggles ────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                TextButton {
                    label: Notifs.doNotDisturb ? "󰂛  DND on" : "󰂚  DND off"
                    accented: Notifs.doNotDisturb
                    onClicked: Notifs.doNotDisturb = !Notifs.doNotDisturb
                }

                TextButton {
                    label: "󰅌  Clipboard"
                    onClicked: Panels.show("clipboard")
                }

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
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
