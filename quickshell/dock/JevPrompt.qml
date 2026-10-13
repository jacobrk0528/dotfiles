import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"

// Bottom-left prompt for artoo (~/dotfiles/artoo). Type a goal ("open youtube on
// workspace 3") or a question; `artoo ask --json` decides which, and streams JSON events
// back. The popup only opens when there's something to read or decide: an answer, an
// "ask first" Run / Cancel, or an error. Plain actions just show progress in the field's icon.
Item {
    id: root

    property string monitorName: ""
    property string originJson: ""
    property bool pendingSubmit: false
    property bool cancelling: false

    // "idle" | "running" | "confirm" | "answer" | "done" | "error"
    property string phase: "idle"
    property bool editing: false
    // Set once the field actually gets the keyboard, so losing it (a click on another
    // window) can end editing without tripping on the moment before focus arrives.
    property bool hadFocus: false
    // Read by Dock.qml for the layer's keyboard mode.
    readonly property bool wantsKeyboard: editing || fieldMouse.containsMouse
    property bool grabbing: false
    property var lines: []
    property string result: ""
    property string confirmMessage: ""
    // The approval popup shows one plain sentence; the step log and the exact operation
    // are behind "Details".
    property bool showDetails: false

    // artoo's approval text (policy.ts authorize) is "<exact operation>\n<what it does, in
    // plain words>[\nYes also allows…]\nAllow this operation?". Other prompts are one line.
    // ask: the sentence to decide on. note: what a yes covers beyond this once. detail: the
    // exact operation.
    readonly property var confirmParts: {
        const lines = root.confirmMessage.split("\n").map(l => l.trim()).filter(l => l !== "");
        if (lines.length && lines[lines.length - 1] === "Allow this operation?")
            lines.pop();
        if (lines.length < 2)
            return { ask: lines[0] ?? "", note: "", detail: "" };
        const rest = lines.slice(1);
        const isNote = l => l.startsWith("Yes also allows");
        return { ask: rest.filter(l => !isNote(l)).join(" "), note: rest.filter(isNote).join(" "), detail: lines[0] };
    }

    implicitWidth: 320

    function startEditing() {
        if (!root.editing && !proc.running) {
            root.originJson = "";
            originProc.running = true;
        }
        root.hadFocus = false;
        root.editing = true;
        input.forceActiveFocus();
    }

    // Super+A: no click to focus an OnDemand layer, so take the keyboard outright. Hold it
    // until the mouse moves (follow_mouse would otherwise hand focus straight back to the
    // window under the pointer); a move drops to OnDemand and Hyprland refocuses that window.
    property var grabCursor: null

    function grabAndEdit() {
        root.grabCursor = null;
        root.grabbing = true;
        cursorPoll.running = true;
        startEditing();
    }

    // Hyprland has no pointer-motion IPC event, so poll the cursor while grabbing.
    Timer {
        interval: 100
        repeat: true
        running: root.grabbing
        onTriggered: cursorPoll.running = true
    }

    Process {
        id: cursorPoll
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let pos;
                try {
                    pos = JSON.parse(text);
                } catch (err) {
                    return;
                }
                if (!root.grabbing)
                    return;
                if (root.grabCursor === null)
                    root.grabCursor = pos;
                // A few pixels of slack so a bumped desk doesn't count as moving.
                else if (Math.abs(pos.x - root.grabCursor.x) + Math.abs(pos.y - root.grabCursor.y) > 4)
                    root.grabbing = false;
            }
        }
    }

    function stopEditing() {
        root.grabbing = false;
        root.editing = false;
        input.focus = false;
    }

    function submit() {
        const text = input.text.trim();
        if (text === "" || proc.running)
            return;
        if (originProc.running) {
            root.pendingSubmit = true;
            return;
        }
        root.cancelling = false;
        root.lines = [];
        root.result = "";
        root.confirmMessage = "";
        root.phase = "running";
        popup.visible = false;
        proc.command = [Quickshell.env("HOME") + "/.local/bin/artoo", "ask", "--json"].concat(root.originJson ? ["--origin", root.originJson] : []).concat(["--", text]);
        input.text = "";
        stopEditing();
        Qt.callLater(() => { if (root.phase === "running") proc.running = true; });
    }

    Process {
        id: originProc
        command: [Quickshell.env("HOME") + "/.local/bin/artoo", "context", "--monitor", root.monitorName]
        stdout: StdioCollector {
            onStreamFinished: {
                try { JSON.parse(text); root.originJson = text.trim(); } catch (err) {}
            }
        }
        onExited: {
            if (root.pendingSubmit) {
                root.pendingSubmit = false;
                root.submit();
            }
        }
    }

    function handle(line) {
        let e;
        try {
            e = JSON.parse(line);
        } catch (err) {
            return;
        }
        switch (e.type) {
        case "status":
            root.lines = root.lines.concat([e.text]);
            if (proc.running && root.phase !== "confirm") {
                root.phase = "running";
                popup.visible = false;
            }
            break;
        case "confirm":
            root.confirmMessage = e.message;
            root.showDetails = false;
            root.phase = "confirm";
            popup.visible = true;
            break;
        case "answer_delta":
            // Stream the answer in as it's generated.
            if (root.phase !== "answer") {
                root.result = "";
                root.phase = "answer";
                popup.visible = true;
            }
            root.result += e.text;
            break;
        case "answer":
            root.result = e.text;
            root.phase = "answer";
            popup.visible = true;
            break;
        case "done":
            root.result = e.text;
            root.finish();
            break;
        case "error":
            root.result = e.text;
            root.phase = "error";
            popup.visible = true;
            break;
        case "cancelled":
            root.cancelling = false;
            root.phase = "idle";
            popup.visible = false;
            break;
        }
    }

    function reply(yes) {
        proc.write(yes ? "y\n" : "n\n");
        root.phase = "running";
        popup.visible = false;
    }

    // Success needs no words: flash a check in the field, then go idle.
    function finish() {
        root.phase = "done";
        popup.visible = false;
        doneFlash.restart();
    }

    function dismiss() {
        popup.visible = false;
        if (proc.running) cancelTask();
        else root.phase = "idle";
    }

    function cancelTask() {
        root.pendingSubmit = false;
        if (proc.running) {
            root.cancelling = true;
            root.lines = root.lines.concat(["Cancelling and restoring your desktop…"]);
            proc.signal(15);
        } else root.phase = "idle";
    }

    Process {
        id: proc
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => root.handle(data)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && root.phase === "running") {
                    root.result = text.trim();
                    root.phase = "error";
                    popup.visible = true;
                }
            }
        }

        onExited: code => {
            root.cancelling = false;
            if (root.phase !== "running")
                return;
            if (code === 0) {
                root.finish();
            } else {
                if (root.result === "")
                    root.result = "artoo exited with " + code;
                root.phase = "error";
                popup.visible = true;
            }
        }
    }

    Timer {
        id: doneFlash
        interval: 1500
        onTriggered: if (root.phase === "done") root.phase = "idle"
    }

    // ── Input field ───────────────────────────────────────────────
    Rectangle {
        id: field
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: 34
        radius: Theme.radius
        color: root.editing ? Theme.activeBg : fieldMouse.containsMouse ? Theme.hoverBg : Theme.alpha(Theme.text, 0.03)
        border.width: 1
        border.color: root.editing ? Theme.alpha(Theme.accent, 0.5) : Theme.pillBorder

        Behavior on color {
            ColorAnimation { duration: Theme.durFast }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingS

            Text {
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
                color: ({ running: Theme.yellow, confirm: Theme.orange, done: Theme.green, error: Theme.red })[root.phase] ?? Theme.accent
                text: ({ running: "󰔟", done: "󰄬", error: "󰅚" })[root.phase] ?? "󰚩"
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                TextInput {
                    id: input
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textPrimary
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectByMouse: true

                    onActiveFocusChanged: {
                        if (activeFocus)
                            root.hadFocus = true;
                        else if (root.editing && root.hadFocus)
                            root.stopEditing();
                    }

                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: {
                        input.text = "";
                        root.stopEditing();
                        if (proc.running) root.cancelTask();
                    }
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: input.text === "" && !root.editing
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: root.phase === "running" ? Theme.textSecondary : Theme.textDim
                    elide: Text.ElideRight
                    // Long tasks show their latest step here instead of a popup.
                    text: root.phase === "running"
                        ? (root.lines.length ? root.lines[root.lines.length - 1].replace(/^ok: /, "") : "working…")
                        : "Ask or do anything…"
                }
            }

            TextButton {
                id: stopButton
                visible: proc.running
                label: root.cancelling ? "Stopping…" : "Stop"
                enabled: !root.cancelling
                onClicked: root.cancelTask()
            }
        }

        MouseArea {
            id: fieldMouse
            anchors.fill: parent
            anchors.rightMargin: stopButton.visible ? stopButton.width + Theme.spacingM : 0
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            // Once editing, let clicks through to the TextInput for cursor placement.
            enabled: !root.editing
            onClicked: {
                if (popup.visible && root.phase !== "running" && root.phase !== "confirm")
                    popup.visible = false;
                root.startEditing();
            }
        }
    }

    // ── Result popup ──────────────────────────────────────────────
    PopupWindow {
        id: popup
        visible: false

        anchor.item: field
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Top | Edges.Right
        anchor.margins.top: -8

        implicitWidth: 440
        implicitHeight: body.implicitHeight + Theme.spacingL * 2

        // Most the scrolling part may take; the header and buttons add about 80 more.
        readonly property int maxScrollHeight: 360
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Theme.tooltipBg
            border.color: Theme.tooltipBorder
            border.width: 1
            radius: Theme.radius

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.letterSpacing: 0.5
                        color: root.phase === "error" ? Theme.red : root.phase === "confirm" ? Theme.orange : Theme.textDim
                        text: ({ confirm: "NEEDS YOUR OK", answer: "ANSWER", error: "ERROR" })[root.phase] ?? ""
                    }

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: closeMouse.containsMouse ? Theme.textPrimary : Theme.textDim
                        text: "✕"

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismiss()
                        }
                    }
                }

                // Everything of variable length scrolls inside a capped area, so the header
                // and the Run / Cancel buttons stay on screen however long the step log is.
                Flickable {
                    id: scroller

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, popup.maxScrollHeight)
                    visible: contentHeight > 0
                    contentHeight: scrollBody.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Dragging is left to text selection; the wheel scrolls.
                    interactive: false

                    readonly property real maxY: Math.max(0, contentHeight - height)

                    function toEnd() {
                        contentY = maxY;
                    }

                    // An approval is asked at the end of the log, so keep the end in view.
                    // An answer is read from its start.
                    onContentHeightChanged: if (root.phase === "confirm") Qt.callLater(toEnd)
                    onHeightChanged: if (root.phase === "confirm") Qt.callLater(toEnd)

                    Connections {
                        target: root
                        function onPhaseChanged() {
                            if (root.phase === "confirm")
                                Qt.callLater(scroller.toEnd);
                            else
                                scroller.contentY = 0;
                        }
                    }

                    WheelHandler {
                        onWheel: event => {
                            scroller.contentY = Math.max(0, Math.min(scroller.maxY, scroller.contentY - event.angleDelta.y));
                        }
                    }

                    ColumnLayout {
                        id: scrollBody
                        width: scroller.width - (scrollBar.visible ? scrollBar.width + Theme.spacingS : 0)
                        spacing: Theme.spacingS

                        Repeater {
                            // The steps so far, for an approval's Details
                            model: root.phase === "confirm" && root.showDetails ? root.lines : []

                            Text {
                                required property string modelData
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textSecondary
                                text: modelData
                            }
                        }

                        TextEdit {
                            Layout.fillWidth: true
                            visible: root.result !== ""
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: root.phase === "error" ? Theme.red : Theme.textPrimary
                            selectionColor: Theme.alpha(Theme.accent, 0.35)
                            text: root.result
                        }

                        // The exact operation being approved
                        Text {
                            Layout.fillWidth: true
                            visible: root.phase === "confirm" && root.showDetails && text !== ""
                            wrapMode: Text.WrapAnywhere
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.textPrimary
                            text: root.confirmParts.detail
                        }
                    }

                    // Scroll position, shown only when there is more than fits
                    Rectangle {
                        id: scrollBar
                        visible: scroller.maxY > 0
                        parent: scroller
                        anchors.right: parent.right
                        width: 3
                        radius: 1.5
                        color: Theme.alpha(Theme.text, 0.25)
                        height: Math.max(24, scroller.height * scroller.height / scroller.contentHeight)
                        y: scroller.maxY > 0 ? (scroller.height - height) * scroller.contentY / scroller.maxY : 0
                    }
                }

                // What it wants to do, in a sentence. Always on screen, with the buttons.
                Text {
                    Layout.fillWidth: true
                    visible: root.phase === "confirm"
                    wrapMode: Text.Wrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textPrimary
                    text: root.confirmParts.ask
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.phase === "confirm" && text !== ""
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.textDim
                    text: root.confirmParts.note
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.phase === "confirm"
                    spacing: Theme.spacingS

                    TextButton {
                        label: "Run it"
                        accented: true
                        accentColor: Theme.orange
                        onClicked: root.reply(true)
                    }

                    TextButton {
                        label: "Cancel"
                        onClicked: root.reply(false)
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    TextButton {
                        visible: root.lines.length > 0 || root.confirmParts.detail !== ""
                        label: root.showDetails ? "Hide details" : "Details"
                        onClicked: root.showDetails = !root.showDetails
                    }
                }
            }
        }
    }
}
