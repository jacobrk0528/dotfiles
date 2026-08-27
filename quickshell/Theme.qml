pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Design tokens for the whole shell. Values come from theme.json, which is
// also read by scripts/apply-theme.sh to propagate the palette to ghostty,
// hyprland and hyprlock. Edits to theme.json apply live.
Singleton {
    id: root

    FileView {
        path: Qt.resolvedUrl("theme.json")
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: cfg

            property string name: "Slate & Frost"

            property string base: "#0d1117"
            property string surface: "#161b22"
            property string text: "#ffffff"
            property string accent: "#8be9fd"

            property string green: "#50fa7b"
            property string yellow: "#f1fa8c"
            property string red: "#ff5555"
            property string pink: "#ff79c6"
            property string orange: "#ffb86c"
            property string purple: "#bd93f9"
            property string gray: "#8b949e"

            property real surfaceOpacity: 0.82
            property real panelOpacity: 0.94
            property real widgetOpacity: 0.42

            property string font: "JetBrainsMono Nerd Font"
            property int fontSize: 12

            property int radius: 10
            property int panelRadius: 16

            property int barHeight: 32
            property int barMargin: 12

            // Empty = desktop widgets on every monitor; otherwise a monitor name.
            property string desktopMonitor: ""
        }
    }

    // ── Palette ──────────────────────────────────────────────────
    readonly property color accent: cfg.accent
    readonly property color green: cfg.green
    readonly property color yellow: cfg.yellow
    readonly property color red: cfg.red
    readonly property color pink: cfg.pink
    readonly property color orange: cfg.orange
    readonly property color purple: cfg.purple
    readonly property color gray: cfg.gray

    // ── Type ─────────────────────────────────────────────────────
    readonly property string fontFamily: cfg.font
    readonly property int fontSize: cfg.fontSize

    // ── Geometry ─────────────────────────────────────────────────
    readonly property int radius: cfg.radius
    readonly property int panelRadius: cfg.panelRadius
    readonly property int barHeight: cfg.barHeight
    readonly property int barMargin: cfg.barMargin
    readonly property string desktopMonitor: cfg.desktopMonitor

    readonly property int spacingS: 6
    readonly property int spacingM: 10
    readonly property int spacingL: 16
    readonly property int spacingXL: 24

    // ── Motion ───────────────────────────────────────────────────
    readonly property int durFast: 150
    readonly property int durMed: 200
    readonly property int durSlow: 320
    readonly property int easing: Easing.OutCubic

    // ── Surfaces ─────────────────────────────────────────────────
    readonly property color pillBg: alpha(cfg.base, cfg.surfaceOpacity)
    readonly property color panelBg: alpha(cfg.base, cfg.panelOpacity)
    readonly property color raised: alpha(cfg.surface, 0.9)
    readonly property color widgetBg: alpha(cfg.base, cfg.widgetOpacity)
    readonly property color widgetBorder: alpha(cfg.text, 0.10)
    readonly property color pillBorder: alpha(cfg.text, 0.08)
    readonly property color tooltipBg: alpha(cfg.base, 0.95)
    readonly property color tooltipBorder: alpha(cfg.text, 0.12)
    readonly property int tooltipFontSize: 13

    // ── Text ─────────────────────────────────────────────────────
    readonly property color textPrimary: alpha(cfg.text, 0.85)
    readonly property color textSecondary: alpha(cfg.text, 0.6)
    readonly property color textDim: alpha(cfg.text, 0.35)

    // ── Interactive states ───────────────────────────────────────
    readonly property color hoverBg: alpha(cfg.text, 0.06)
    readonly property color activeBg: alpha(cfg.text, 0.1)
    readonly property color pressedBg: alpha(cfg.text, 0.16)
    readonly property color separator: alpha(cfg.text, 0.06)

    // Workspace pill states (kept as named tokens for the bar)
    readonly property color wsActiveBg: activeBg
    readonly property color wsActiveFg: alpha(cfg.text, 0.9)
    readonly property color wsHoverBg: hoverBg
    readonly property color wsHoverFg: alpha(cfg.text, 0.65)
    readonly property color wsUrgentBg: Qt.rgba(235 / 255, 77 / 255, 75 / 255, 0.45)

    // ── Helpers ──────────────────────────────────────────────────
    function alpha(c, a) {
        const col = Qt.color(c);
        return Qt.rgba(col.r, col.g, col.b, a);
    }

    // Green under `good`, yellow under `warn`, red above.
    function statusColor(value, good, warn) {
        if (value < good)
            return root.green;
        if (value < warn)
            return root.yellow;
        return root.red;
    }

    // Convert pango markup emitted by the shell scripts into Qt rich text.
    function pangoToRichText(s) {
        if (!s)
            return "";
        return s
            .replace(/&/g, "&amp;")
            .replace(/&amp;(amp|lt|gt|quot|#\d+);/g, "&$1;")
            .replace(/<span color=(["'])(#?\w+)\1>/g, '<font color="$2">')
            .replace(/<\/span>/g, "</font>")
            .replace(/\n/g, "<br>");
    }
}
