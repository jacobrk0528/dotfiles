import QtQuick
import ".."
import "../components"
import "../services"

// Dictation status in the bar. Collapses to nothing when idle.
BarModule {
    id: root

    readonly property bool listening: Dictation.state === "listening" || Dictation.state === "teaching" || Dictation.state === "no-input"

    icon: {
        switch (Dictation.state) {
        case "listening":
            return "󰍬";
        case "teaching":
            return "󰑫";
        case "no-input":
            return "󰍭";
        case "transcribing":
            return "󰔟";
        default:
            return "";
        }
    }

    text: {
        switch (Dictation.state) {
        case "listening":
            return "listening";
        case "teaching":
            return "teaching";
        case "no-input":
            return "no audio - mic muted?";
        case "transcribing":
            return "transcribing";
        default:
            return "";
        }
    }

    textColor: {
        switch (Dictation.state) {
        case "listening":
            return Theme.red;
        case "teaching":
            return Theme.purple;
        case "no-input":
            return Theme.orange;
        default:
            return Theme.yellow;
        }
    }

    tooltipText: Dictation.state === "no-input"
        ? "Recording, but the mic is delivering silence - check mute"
        : root.listening ? "Dictation is recording" : "Transcribing what you said"

    // Breathe while the mic is open, so it reads as live rather than stuck.
    SequentialAnimation {
        running: root.listening
        loops: Animation.Infinite
        alwaysRunToEnd: true

        NumberAnimation {
            target: root
            property: "opacity"
            to: 0.45
            duration: 700
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: 700
            easing.type: Easing.InOutQuad
        }

        onRunningChanged: {
            if (!running)
                root.opacity = 1;
        }
    }
}
