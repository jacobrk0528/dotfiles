import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Tiny one-shot AI prompt. Type a question and get an answer, or tell it to
// do something ("open Chrome") and it does it — backed by the `claude` CLI
// (this machine's Claude Code subscription) running headless with Bash so
// it can actually act, not just reply. Independent of the desktop widget
// (desktop/AiCard.qml) — each runs its own `claude` process, so asking here
// doesn't interrupt one still working on the desktop.
//
// AiShot.qml captures a screenshot of the focused monitor and only then
// opens this panel (Panels.show("ai")) — before this layer's blur
// (hypr/hyprland.lua, "quickshell-overlay" namespace) is applied, so the
// screenshot handed to Claude via the Read tool is the real screen, not a
// blurred one.
Overlay {
    id: root

    panelName: "ai"
    contentAlign: Qt.AlignTop

    // Fast model: this is for quick answers/actions, not deep reasoning.
    property string model: "haiku"

    // "idle" | "thinking" | "done" | "error"
    property string state: "idle"
    property string response: ""

    onShownChanged: {
        if (shown) {
            input.text = "";
            root.state = "idle";
            root.response = "";
            input.forceActiveFocus();
        } else {
            proc.running = false;
        }
    }

    function ask() {
        const message = input.text.trim();
        if (message === "" || root.state === "thinking")
            return;

        root.state = "thinking";
        root.response = "";

        const tools = AiShot.ready ? "Bash,Read,WebSearch" : "Bash,WebSearch";
        const fullMessage = AiShot.ready ? "A screenshot of my screen, taken just now, is at " + AiShot.path + " — read it if it's relevant to this. " + message : message;

        proc.command = ["claude", "-p", "--output-format", "text", "--model", root.model, "--permission-mode", "bypassPermissions", "--tools", tools, "--no-session-persistence", "--append-system-prompt", "You are a tiny desktop quick-assistant, one shot, no follow-up turns. Answer plainly in a sentence or two, no markdown. If asked to do something on this computer (open an app, run a command), just do it with the Bash tool — background/detach GUI apps (setsid ... &) so they survive after you exit — then confirm briefly what you did.", fullMessage];
        proc.running = true;
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                root.response = text.trim();
                root.state = root.response === "" ? "error" : "done";
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (root.state !== "done" && text.trim() !== "") {
                    root.response = text.trim();
                    root.state = "error";
                }
            }
        }
    }

    // Hidden, unwrapped copies of the input/response text used only to
    // measure how wide they'd naturally render, so the card can grow to fit
    // them (rather than always wrapping/clipping at a fixed width).
    Text {
        id: inputMeasure
        visible: false
        wrapMode: Text.NoWrap
        font.family: Theme.fontFamily
        font.pixelSize: 18
        text: input.text
    }

    Text {
        id: responseMeasure
        visible: false
        wrapMode: Text.NoWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        text: root.response
    }

    Card {
        id: card
        readonly property real minWidth: 560
        readonly property real maxWidth: root.screen.width * 2 / 3
        readonly property real maxResponseHeight: root.screen.height * 0.6

        // Room the input row needs besides the input text itself: icon +
        // spacing, plus the "sees your screen" hint when it's showing.
        readonly property real inputRowChrome: icon.implicitWidth + Theme.spacingM + (hint.visible ? Theme.spacingM + hint.implicitWidth : 0)

        // Whether the input text alone needs more than the max width — i.e.
        // whether it actually needs to wrap. Used to keep the TextEdit in
        // NoWrap mode below the cap: RowLayout/ColumnLayout only apply a
        // Layout.fillWidth item's new width on the next polish pass (one
        // frame after a binding changes card's width), so while wrapping is
        // live it can briefly re-wrap against that stale, too-narrow width
        // and then snap back once the layout catches up — a spurious line
        // that flashes in and out while typing. There's never a real need to
        // wrap below the cap (the card just grows to fit), so wrapping stays
        // off there and only turns on once we're pinned at maxWidth.
        readonly property bool inputNeedsWrap: inputMeasure.contentWidth + inputRowChrome + Theme.spacingL * 2 > maxWidth

        width: Math.max(minWidth, Math.min(Math.max(inputMeasure.contentWidth + inputRowChrome, responseMeasure.contentWidth) + Theme.spacingL * 2, maxWidth))
        height: layout.implicitHeight + Theme.spacingL * 2

        Behavior on height {
            NumberAnimation { duration: Theme.durMed; easing.type: Theme.easing }
        }

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            // ── Input ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                Text {
                    id: icon
                    Layout.alignment: Qt.AlignTop
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.accent
                    text: root.state === "thinking" ? "󰚩" : "󰭹"
                }

                TextEdit {
                    id: input

                    Layout.fillWidth: true
                    focus: true
                    enabled: root.state !== "thinking"

                    wrapMode: card.inputNeedsWrap ? TextEdit.Wrap : TextEdit.NoWrap
                    clip: true
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.textPrimary
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.textPrimary

                    Keys.onEscapePressed: Panels.close()
                    Keys.onReturnPressed: event => {
                        event.accepted = true;
                        root.ask();
                    }
                    Keys.onEnterPressed: event => {
                        event.accepted = true;
                        root.ask();
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === ""
                        font: input.font
                        color: Theme.textDim
                        text: "Ask something, or tell it to do something…"
                    }
                }

                Text {
                    id: hint
                    Layout.alignment: Qt.AlignTop
                    visible: AiShot.ready && root.state === "idle"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.textDim
                    text: "󰄀  sees your screen"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
                visible: root.state !== "idle"
            }

            // ── Response ─────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                visible: root.state === "thinking"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textDim
                text: "Thinking…"
            }

            Flickable {
                Layout.fillWidth: true
                implicitHeight: Math.min(response.implicitHeight, card.maxResponseHeight)
                visible: root.state === "done" || root.state === "error"
                clip: true
                contentWidth: width
                contentHeight: response.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: response
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: root.state === "error" ? Theme.red : Theme.textPrimary
                    text: root.response
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacingS
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                color: Theme.textDim
                text: "Enter to ask · Esc to close"
            }
        }
    }
}
