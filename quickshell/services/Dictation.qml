pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// What the push-to-talk dictation daemon is doing, published by
// hypr/scripts/ptt-dictate/daemon.py so the bar can show it instead of the
// daemon firing a notification for every phrase.
Singleton {
    id: root

    // "idle" | "listening" | "teaching" | "transcribing"
    readonly property string state: adapter.state
    readonly property bool active: root.state !== "" && root.state !== "idle"

    FileView {
        // Runtime state, so it resets on reboot rather than persisting a
        // stale "listening" if the daemon is killed mid-phrase.
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/ptt-dictate.state"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property string state: "idle"
        }
    }
}
