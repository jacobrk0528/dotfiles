pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool enabled: false
    property int temperature: 2500
    property bool scheduleEnabled: true
    property string start: "18:00"
    property string end: "08:00"
    property string error: ""
    property var queue: []
    readonly property string script: Quickshell.env("HOME") + "/dotfiles/hypr/scripts/night-mode"

    function request(args) {
        let commands = queue.slice();
        if (args[0] === "set" && commands.length && commands[commands.length - 1][0] === "set")
            commands.pop();
        commands.push(args);
        queue = commands;
        pump();
    }

    function pump() {
        if (proc.running || queue.length === 0) return;
        let commands = queue.slice();
        let args = commands.shift();
        queue = commands;
        proc.command = [script].concat(args);
        proc.running = true;
    }

    function saveSchedule(enabled, start, end) {
        request(["schedule", enabled ? "on" : "off", start, end]);
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const settings = JSON.parse(text);
                    root.enabled = settings.enabled;
                    root.temperature = settings.temperature;
                    root.scheduleEnabled = settings.scheduleEnabled;
                    root.start = settings.start;
                    root.end = settings.end;
                } catch (e) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") root.error = text.trim();
            }
        }
        onExited: code => {
            if (code === 0) root.error = "";
            else if (root.error === "") root.error = "Couldn't update night mode";
            root.pump();
        }
    }

    // The script catches missed boundaries after suspend.
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!proc.running && root.queue.length === 0) root.request(["tick"]);
        }
    }
}
