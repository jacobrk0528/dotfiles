import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Frozen copy of the screen shown under slurp by scripts/screenshot-region,
// so popups that close when slurp takes focus (dropdowns, context menus) stay
// visible while the region is dragged out. The script grabs the whole layout
// with grim first, then:
//   qs ipc call freeze open <path>
//   qs ipc call freeze close
// Each monitor shows its own slice of that one capture. grim's full capture
// spans the layout's bounding box at the highest output scale, so the origin
// and scale are worked out here from the screens. (They can't be passed in:
// `qs ipc call` reads a negative origin like -1920 as an unknown flag. Nor
// can the functions be named show/hide: `qs ipc call freeze show` runs
// `qs ipc show` instead.)
Scope {
    id: root

    property string path: ""
    readonly property int originX: Math.min(...Quickshell.screens.map(s => s.x))
    readonly property int originY: Math.min(...Quickshell.screens.map(s => s.y))
    readonly property real scale: Math.max(...Quickshell.screens.map(s => s.devicePixelRatio))

    IpcHandler {
        target: "freeze"

        function open(path: string): void {
            root.path = path;
        }

        function close(): void {
            root.path = "";
        }
    }

    Variants {
        model: root.path === "" ? [] : Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "black"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-freeze"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Image {
                anchors.fill: parent
                source: "file://" + root.path
                asynchronous: false
                cache: false
                smooth: false
                sourceClipRect: Qt.rect((modelData.x - root.originX) * root.scale,
                                        (modelData.y - root.originY) * root.scale,
                                        modelData.width * root.scale,
                                        modelData.height * root.scale)
            }
        }
    }
}
