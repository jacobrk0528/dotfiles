import QtQuick
import ".."

// HSV wheel: hue by angle, saturation by radius, fixed full value. Drag to
// pick a color. Emits colorPicked only on release (not while dragging) so
// callers don't hammer a network API on every mouse-move.
//
// Rendered as a ring of thin rotated spokes (white-to-hue gradient along
// each), not a Canvas — a first version used a Canvas with a per-pixel JS
// fill, which QtQuick kept repainting every frame and pegged a CPU core
// solid. This version is pure declarative Items/transforms, so it's just
// normal GPU-composited geometry with no per-frame JS cost.
//
// interactive: false renders a static wheel (used as a small icon/button)
// with no drag handling of its own — wrap it in an external MouseArea for
// a click-to-open affordance instead.
Item {
    id: root

    property int diameter: 160
    property bool interactive: true
    property int spokeCount: 60
    signal colorPicked(int r, int g, int b)

    implicitWidth: diameter
    implicitHeight: diameter

    readonly property real radius: diameter / 2

    function hsvToRgb(h, s, v) {
        const c = v * s;
        const x = c * (1 - Math.abs((h / 60) % 2 - 1));
        const m = v - c;
        let r1 = 0, g1 = 0, b1 = 0;
        if (h < 60) {
            r1 = c; g1 = x; b1 = 0;
        } else if (h < 120) {
            r1 = x; g1 = c; b1 = 0;
        } else if (h < 180) {
            r1 = 0; g1 = c; b1 = x;
        } else if (h < 240) {
            r1 = 0; g1 = x; b1 = c;
        } else if (h < 300) {
            r1 = x; g1 = 0; b1 = c;
        } else {
            r1 = c; g1 = 0; b1 = x;
        }
        return [Math.round((r1 + m) * 255), Math.round((g1 + m) * 255), Math.round((b1 + m) * 255)];
    }

    Repeater {
        model: root.spokeCount

        Rectangle {
            required property int index

            readonly property real angle: (index / root.spokeCount) * 360
            readonly property var rgb: root.hsvToRgb(angle, 1, 1)

            x: root.radius
            y: root.radius - height / 2
            width: root.radius
            // Thin enough that adjacent spokes' outer corners barely
            // overshoot the circle (negligible at this radius/count), but
            // thick enough to fully cover the gap between spokes.
            height: (2 * Math.PI * root.radius / root.spokeCount) * 1.6
            transformOrigin: Item.Left
            rotation: angle

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "white" }
                GradientStop { position: 1.0; color: Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1) }
            }
        }
    }

    Rectangle {
        id: handle
        visible: false
        width: 14
        height: 14
        radius: 7
        color: "transparent"
        border.width: 2
        border.color: "white"
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive

        function updateFromPos(px, py) {
            const dx = px - root.radius;
            const dy = py - root.radius;
            const dist = Math.min(Math.sqrt(dx * dx + dy * dy), root.radius);
            const angleRad = Math.atan2(dy, dx);
            let angle = angleRad * 180 / Math.PI;
            if (angle < 0)
                angle += 360;
            const sat = dist / root.radius;
            const rgb = root.hsvToRgb(angle, sat, 1);

            handle.x = root.radius + Math.cos(angleRad) * dist - handle.width / 2;
            handle.y = root.radius + Math.sin(angleRad) * dist - handle.height / 2;
            handle.visible = true;

            return rgb;
        }

        onPressed: mouse => updateFromPos(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            if (pressed)
                updateFromPos(mouse.x, mouse.y);
        }
        onReleased: mouse => {
            const rgb = updateFromPos(mouse.x, mouse.y);
            root.colorPicked(rgb[0], rgb[1], rgb[2]);
        }
    }
}
