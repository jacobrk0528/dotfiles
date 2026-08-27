pragma Singleton
import Quickshell
import QtQuick

// Shared geometry for the transient overlays that share the top-right corner.
// They are separate layer-shell windows and cannot measure each other, so the
// notification stack publishes its height here and the now-playing OSD sits
// below it instead of overlapping.
Singleton {
    property real notifHeight: 0
}
