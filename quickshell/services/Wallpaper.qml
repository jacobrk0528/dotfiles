pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Current wallpaper, shared by the desktop layer and the picker.
//
// The shell draws the wallpaper itself rather than running hyprpaper: 0.8.4
// refuses to bind a wallpaper to any monitor here ("has no target"), and
// drawing it in-process gives us crossfades and one less daemon.
Singleton {
    id: root

    readonly property string path: adapter.path

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/dotfiles/hypr/wallpaper.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property string path: ""
        }
    }
}
