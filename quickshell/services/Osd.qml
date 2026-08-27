pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Drives the on-screen display. Watches audio state and raises the OSD
// whenever something changes from outside the shell (media keys, mixers).
Singleton {
    id: root

    // "volume" | "mute" | "source"
    property string kind: "volume"
    property bool active: false

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    // Ignore the initial binding evaluation so the OSD doesn't flash at startup.
    property bool ready: false

    function show(what) {
        if (!root.ready)
            return;
        root.kind = what;
        root.active = true;
        hideTimer.restart();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    onVolumeChanged: root.show("volume")
    onMutedChanged: root.show("mute")
    onSinkChanged: root.show("source")

    Timer {
        id: hideTimer
        interval: 1800
        onTriggered: root.active = false
    }

    Timer {
        interval: 800
        running: true
        onTriggered: root.ready = true
    }
}
