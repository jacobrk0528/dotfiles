import QtQuick
import ".."
import "../components"
import "../services"

// Dictation status in the bar. Collapses to nothing when idle.
BarModule {
    id: root

    readonly property bool listening: Dictation.state === "listening" || Dictation.state === "teaching"

    icon: {
        switch (Dictation.state) {
        case "listening":
            return "󰍬";
        case "teaching":
            return "󰑫";
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
        default:
            return Theme.yellow;
        }
    }

    tooltipText: root.listening ? "Dictation is recording" : "Transcribing what you said"

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
