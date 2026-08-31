import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."

// Desktop-resident twin of panels/Ai.qml: always-visible quick-ask box, no
// SUPER+A needed. Runs its own `claude` process, independent of the overlay
// one, so the two can be mid-answer at the same time without conflict.
ColumnLayout {
    id: root

    // Fast model: this is for quick answers/actions, not deep reasoning.
    property string model: "haiku"

    // "idle" | "thinking" | "done" | "error"
    property string state: "idle"
    property string response: ""

    spacing: Theme.spacingS

    function ask() {
        const message = input.text.trim();
        if (message === "" || root.state === "thinking")
            return;

        root.state = "thinking";
        root.response = "";
        proc.command = ["claude", "-p", "--output-format", "text", "--model", root.model, "--permission-mode", "bypassPermissions", "--tools", "Bash,WebSearch", "--no-session-persistence", "--append-system-prompt", "You are a tiny desktop quick-assistant, one shot, no follow-up turns. Answer plainly in a sentence or two, no markdown. If asked to do something on this computer (open an app, run a command), just do it with the Bash tool — background/detach GUI apps (setsid ... &) so they survive after you exit — then confirm briefly what you did.", message];
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

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingM

        Text {
            font.family: Theme.fontFamily
            font.pixelSize: 16
            color: Theme.accent
            text: root.state === "thinking" ? "󰚩" : "󰭹"
        }

        TextInput {
            id: input

            Layout.fillWidth: true
            enabled: root.state !== "thinking"

            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            color: Theme.alpha("#ffffff", 0.9)
            selectionColor: Theme.alpha(Theme.accent, 0.35)
            selectedTextColor: Theme.alpha("#ffffff", 0.9)
            clip: true

            Keys.onEscapePressed: {
                input.text = "";
                root.state = "idle";
                root.response = "";
                input.focus = false;
            }
            Keys.onReturnPressed: root.ask()
            Keys.onEnterPressed: root.ask()

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: mouse => {
                    input.forceActiveFocus();
                    mouse.accepted = false;
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                font: input.font
                color: Theme.alpha("#ffffff", 0.35)
                text: "Ask the AI…"
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: root.state === "thinking"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: Theme.alpha("#ffffff", 0.55)
        text: "Thinking…"
    }

    Text {
        Layout.fillWidth: true
        visible: root.state === "done" || root.state === "error"
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: root.state === "error" ? Theme.red : Theme.alpha("#ffffff", 0.8)
        text: root.response
    }
}
