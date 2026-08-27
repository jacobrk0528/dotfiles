import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."
import "../services"

// Wallpaper layer. Two images crossfade so switching never flashes.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: Theme.alpha("#000000", 1)
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Never take input; this sits under everything.
    mask: Region {}

    // Which of the two layers currently holds the visible image.
    property bool useA: true
    property string pending: ""

    onPendingChanged: {}

    Connections {
        target: Wallpaper

        function onPathChanged() {
            if (Wallpaper.path === "")
                return;
            // Load into the hidden layer, then fade it in.
            if (root.useA)
                imageB.source = "file://" + Wallpaper.path;
            else
                imageA.source = "file://" + Wallpaper.path;
        }
    }

    Image {
        id: imageA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: root.useA ? 1 : 0
        source: Wallpaper.path === "" ? "" : "file://" + Wallpaper.path

        onStatusChanged: {
            if (status === Image.Ready && !root.useA)
                root.useA = true;
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durSlow
                easing.type: Theme.easing
            }
        }
    }

    Image {
        id: imageB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: root.useA ? 0 : 1

        onStatusChanged: {
            if (status === Image.Ready && root.useA)
                root.useA = false;
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durSlow
                easing.type: Theme.easing
            }
        }
    }
}
