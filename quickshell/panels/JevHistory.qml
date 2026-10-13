import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// artoo conversations (SUPER+SHIFT+A), newest first: what was asked, what came back, how
// long it took and roughly what it cost. Enter or click opens one: every step, tool call and
// command output, plus the Jev picks from any desktop task it ran. Each has a short id
// (!12): typing that in a later prompt hands artoo the record of that conversation, as in
// "do what you did in !12 again". Data comes from
// `artoo history --json` (~/.local/share/artoo/conversations/).
Overlay {
    id: root

    panelName: "jev-history"
    contentAlign: Qt.AlignTop

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/artoo"

    property var conversations: []
    // The open conversation's detail, or null for the list
    property var detail: null
    property bool loading: false

    onShownChanged: {
        if (shown) {
            root.detail = null;
            search.text = "";
            list.currentIndex = 0;
            root.loading = true;
            listProc.running = true;
            search.forceActiveFocus();
        }
    }

    readonly property var filtered: {
        const q = search.text.trim().toLowerCase();
        if (q === "")
            return root.conversations;
        // "!12" finds that conversation alone, not !120 or the ones that mention it
        if (/^!\d+$/.test(q))
            return root.conversations.filter(c => "!" + c.ref === q);
        return root.conversations.filter(c => (c.input + " " + c.output).toLowerCase().includes(q));
    }

    Process {
        id: listProc
        command: [root.bin, "history", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    root.conversations = JSON.parse(text);
                } catch (e) {
                    root.conversations = [];
                }
            }
        }
    }

    Process {
        id: detailProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.detail = JSON.parse(text);
                    stepsView.positionViewAtBeginning();
                    stepsView.forceActiveFocus();
                } catch (e) {
                    root.detail = null;
                }
            }
        }
    }

    Process {
        id: copyProc
    }

    // True for a moment after copying, so the button can confirm it
    property bool copied: false

    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: root.copied = false
    }

    // Unlike the dictation panel this leaves the overlay open: copying the
    // prompt is usually a step in reading the conversation, not the end of it.
    function copyInput() {
        const text = root.detail?.input ?? "";
        if (text === "")
            return;
        // text/plain forced for the same reason as the clipboard panel
        copyProc.command = ["wl-copy", "--type", "text/plain", "--", text];
        copyProc.running = true;
        root.copied = true;
        copiedTimer.restart();
    }

    function open(c) {
        if (!c)
            return;
        detailProc.command = [root.bin, "history", "--json", c.id];
        detailProc.running = true;
    }

    function back() {
        root.detail = null;
        search.forceActiveFocus();
    }

    // "14:02" today, "Sep 28 14:02" otherwise
    function formatWhen(ts) {
        const d = new Date(ts);
        const time = Qt.formatDateTime(d, "HH:mm");
        return d.toDateString() === new Date().toDateString() ? time : Qt.formatDateTime(d, "MMM d") + " " + time;
    }

    function formatMs(ms) {
        if (ms === undefined || ms === null)
            return "—";
        return ms < 1000 ? ms + "ms" : (ms / 1000).toFixed(1) + "s";
    }

    // Estimates from prices.yaml; null means some model used has no price.
    function formatCost(cost) {
        if (cost === undefined || cost === null)
            return "—";
        return cost < 0.01 ? "$" + cost.toFixed(4) : "$" + cost.toFixed(3);
    }

    function statusColor(s) {
        return ({ answer: Theme.accent, done: Theme.green, error: Theme.red, cancelled: Theme.yellow })[s] ?? Theme.textDim;
    }

    // One timeline row per event: { label, text, mono, color }. Status lines that just repeat
    // the next command's "why" are dropped.
    function steps(d) {
        if (!d)
            return [];
        const out = [];
        const t0 = d.started;
        const evs = d.events;
        // The run log already holds each plan and executed step; the status lines that echo
        // them ("Inspecting…", the plan's message, "ok: …") would show everything twice.
        const planned = new Set();
        for (const r of d.runs)
            for (const re of r.events)
                if (re.type === "plan" && re.message)
                    planned.add(re.message);
        for (let i = 0; i < evs.length; i++) {
            const e = evs[i];
            const at = "+" + root.formatMs(e.t - t0);
            switch (e.type) {
            case "start":
            case "end":
            case "answer_delta":
                break;
            case "route":
                out.push({ at, ms: e.t, label: "route", text: e.route + " (" + Math.round(e.confidence * 100) + "% sure)", color: Theme.textSecondary });
                break;
            case "status":
                if (evs.some(x => x.type === "tool_call" && x.why === e.text))
                    break;
                if (planned.has(e.text) || /^(ok: |Inspecting |Reading )/.test(e.text))
                    break;
                out.push({ at, ms: e.t, label: /^failed/.test(e.text) ? "failed" : "status", text: e.text, color: /^failed/.test(e.text) ? Theme.yellow : Theme.textSecondary });
                break;
            case "tool_call":
                if (e.name === "desktop_task")
                    out.push({ at, ms: e.t, label: "desktop", text: e.goal, color: Theme.accent });
                else if (e.name === "web_search")
                    out.push({ at, ms: e.t, label: "search", text: e.query || "(web search)", color: Theme.accent });
                else
                    out.push({ at, ms: e.t, label: "run", text: (e.why ? e.why + "\n" : "") + "$ " + e.command, mono: true, color: Theme.accent });
                break;
            case "tool_result":
                out.push({ at, ms: e.t, label: "output", text: (e.output ?? e.message ?? "") + (e.code ? "\n[exit " + e.code + "]" : ""), mono: true, color: Theme.textDim, collapsible: true });
                break;
            case "confirm":
                out.push({ at, ms: e.t, label: "ask", text: e.message, color: Theme.yellow });
                break;
            case "confirm_answer":
                out.push({ at, ms: e.t, label: "you", text: e.ok ? "Approved" : "Declined", color: e.ok ? Theme.green : Theme.yellow });
                break;
            case "answer":
            case "done":
            case "error":
            case "cancelled":
                out.push({ at, ms: e.t, label: e.type, text: e.text, color: root.statusColor(e.type) });
                break;
            case "run_log":
                for (const r of d.runs.filter(r => r.dir === e.dir))
                    for (const re of r.events)
                        out.push(root.runStep(re, t0));
                break;
            case "references":
                out.push({ at, ms: e.t, label: "uses", text: e.refs.map(r => "!" + r).join(", "), color: Theme.textSecondary });
                break;
            case "desktop_origin":
                // Bookkeeping for restoring the desktop afterwards; nothing to read here
                break;
            default:
                out.push({ at, ms: e.t, label: e.type, text: JSON.stringify(Object.assign({}, e, { t: undefined, type: undefined })), color: Theme.textDim });
            }
        }
        // Run-log events arrive in one block at the point their log was opened; put
        // everything back in the order it happened. Rows without a time keep their place.
        const rows = out.filter(Boolean).map((r, i) => Object.assign(r, { order: i }));
        let last = t0;
        for (const r of rows)
            last = r.ms = r.ms ?? last;
        rows.sort((a, b) => a.ms - b.ms || a.order - b.order);
        return rows;
    }

    // "click t2: cell A752" / "keys → 9/8/26⇥Discover⏎" for one planned operation
    function describeOp(o) {
        if (!o || typeof o !== "object" || !o.action)
            return "";
        const seq = (o.sequence ?? []).map(x => x === "{tab}" ? "⇥" : x === "{enter}" ? "⏎\n" : x).join("");
        const what = [o.target, o.key, o.text !== null && o.text !== undefined ? JSON.stringify(o.text) : null].filter(Boolean).join(" ");
        const where = o.pane && !(o.target ?? "").startsWith(o.pane) ? " in " + o.pane : "";
        return o.action.replace("_", " ") + (what ? " " + what : "") + (o.direction ? " " + o.direction : "") + where + (seq ? "\n" + seq.trim() : "");
    }

    function parse(v) {
        if (typeof v !== "string")
            return v;
        try {
            return JSON.parse(v);
        } catch (e) {
            return v;
        }
    }

    // Events from a desktop task's runs/<ts>/events.jsonl
    function runStep(e, t0) {
        const at = "+" + root.formatMs(e.t - t0);
        const ms = e.t;
        const pct = c => Math.round(c * 100) + "%";
        switch (e.type) {
        case "observation": {
            const panes = root.parse(e.panes);
            const context = root.parse(e.context) ?? {};
            const title = Array.isArray(panes) && panes.length ? panes.map(p => p.title).join("  |  ") : (context.window ?? context.page_title ?? e.id);
            return { at, ms, label: "screen", text: title + "\n" + (e.content ?? ""), image: e.image ? "file://" + e.image : "", color: Theme.textDim, collapsible: true, lines: 1 };
        }
        case "task_progress": {
            const list = v => Array.isArray(root.parse(v)) ? root.parse(v) : [];
            const checked = list(e.checked);
            const pending = list(e.pending);
            if (!checked.length && !pending.length)
                return null;
            return { at, ms, label: "checked", text: checked.map(f => f.key + ": " + f.result).concat(pending.length ? ["Pending: " + pending.join(", ")] : []).join("\n"), color: Theme.textSecondary, collapsible: true };
        }
        case "plan": {
            const planSteps = root.parse(e.steps);
            const op = root.describeOp(Array.isArray(planSteps) ? planSteps[0] : null);
            const finished = e.status !== "continue";
            return { at, ms, label: finished ? e.status : "plan", text: (e.message ?? "") + (op ? "\n→ " + op : ""), color: finished ? root.statusColor(e.status) : Theme.accent, collapsible: true };
        }
        case "step":
            return { at, ms, label: e.effect === "write" || e.effect === "destructive" ? "edit" : "did", text: e.what, color: e.effect === "navigate" ? Theme.green : Theme.yellow, collapsible: true, lines: 2 };
        case "pick_window":
            return { at, ms, label: "window", text: e.title + "  ·  workspace " + e.workspace + "  ·  " + e.surface + (e.confidence !== undefined ? "  ·  " + pct(Number(e.confidence)) : ""), color: Theme.textSecondary };
        case "ocr_error":
        case "restore_error":
            return { at, ms, label: "error", text: e.message, color: Theme.red };
        case "approval":
            return { at, ms, label: e.approved ? (e.standing ? "allowed" : "approved") : "declined", text: e.summary + "\n" + (e.reason ?? ""), color: e.approved ? Theme.green : Theme.yellow, collapsible: true, lines: 3 };
        case "verification":
            return { at, ms, label: "verify", text: e.reason, color: e.supported ? Theme.green : Theme.yellow };
        case "desktop_restored":
            return { at, ms, label: "returned", text: e.monitor + " · " + e.window, color: Theme.textSecondary };
        case "goal":
        case "state":
            return null;
        case "pick_action":
            return { at, ms, label: "jev", text: "action " + e.key + " (" + pct(e.confidence) + ")" + (e.top ? "  · " + e.top.map(t => t[0] + " " + pct(t[1])).join(", ") : ""), color: Theme.textSecondary };
        case "pick_param":
            return { at, ms, label: "jev", text: e.param + " = " + e.value + " (" + pct(e.confidence) + ")", color: Theme.textSecondary };
        case "result":
            return { at, ms, label: "result", text: e.status + (e.message ? ": " + e.message : "") + (e.reasons ? ": " + e.reasons.join(", ") : ""), color: root.statusColor(e.status === "declined" ? "cancelled" : e.status) };
        default: {
            const rest = Object.assign({}, e);
            delete rest.t;
            delete rest.type;
            return { at, ms, label: e.type.replace(/_/g, " "), text: JSON.stringify(rest), mono: true, color: Theme.textDim, collapsible: true, lines: 2 };
        }
        }
    }

    Card {
        width: 860
        height: layout.implicitHeight + Theme.spacingL * 2

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            // ── List ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                visible: root.detail === null
                spacing: Theme.spacingM

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.accent
                    text: "󰚩"
                }

                TextInput {
                    id: search

                    Layout.fillWidth: true
                    focus: true
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: Theme.textPrimary
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.textPrimary
                    clip: true

                    onTextChanged: list.currentIndex = 0

                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onEscapePressed: Panels.close()
                    Keys.onReturnPressed: root.open(root.filtered[list.currentIndex])
                    Keys.onEnterPressed: root.open(root.filtered[list.currentIndex])

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        font: search.font
                        color: Theme.textDim
                        text: "Search artoo conversations…"
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                    text: {
                        const n = root.filtered.length;
                        const cost = root.filtered.reduce((s, c) => s + (c.cost ?? 0), 0);
                        return n + " conversation" + (n === 1 ? "" : "s") + (cost > 0 ? " · " + root.formatCost(cost) : "");
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.separator
            }

            ListView {
                id: list

                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, 560)
                visible: root.detail === null && root.filtered.length > 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.filtered

                delegate: MouseArea {
                    id: row

                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: rowLayout.implicitHeight + 16
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: list.currentIndex = index
                    onClicked: root.open(modelData)

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: list.currentIndex === row.index ? Theme.activeBg : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.durFast
                            }
                        }
                    }

                    RowLayout {
                        id: rowLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingM

                        // The id to type in a later prompt
                        Text {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 40
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.accent
                            text: row.modelData.ref !== undefined ? "!" + row.modelData.ref : ""
                        }

                        Text {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 90
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.textDim
                            text: root.formatWhen(row.modelData.started)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                text: row.modelData.input
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textSecondary
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: row.modelData.output
                            }
                        }

                        // Stats: status · time · cost · tools
                        Text {
                            Layout.alignment: Qt.AlignTop
                            horizontalAlignment: Text.AlignRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            textFormat: Text.StyledText
                            color: Theme.textDim
                            text: "<font color='" + root.statusColor(row.modelData.status) + "'>" + row.modelData.status + "</font>"
                                + "  " + root.formatMs(row.modelData.ms)
                                + "  " + root.formatCost(row.modelData.cost)
                                + (row.modelData.toolCalls ? "  󰆍 " + row.modelData.toolCalls : "")
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingL
                Layout.bottomMargin: Theme.spacingL
                visible: root.detail === null && root.filtered.length === 0
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textDim
                text: root.loading ? "Loading…" : root.conversations.length === 0 ? "No conversations yet" : "No matches"
            }

            // ── Detail ────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.detail !== null
                spacing: Theme.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    IconButton {
                        Layout.alignment: Qt.AlignTop
                        glyph: "󰁍"
                        size: 22
                        onClicked: root.back()
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        color: Theme.textPrimary
                        wrapMode: Text.Wrap
                        text: root.detail?.input ?? ""
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignTop
                        glyph: root.copied ? "󰄬" : "󰆏"
                        size: 22
                        onClicked: root.copyInput()
                    }
                }

                // Stats
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spacingL

                    Repeater {
                        model: {
                            const d = root.detail;
                            if (!d)
                                return [];
                            const usage = (d.events.find(e => e.type === "end") ?? {}).usage;
                            const items = [
                                ["id", d.ref !== undefined ? "!" + d.ref : "—"],
                                ["when", Qt.formatDateTime(new Date(d.started), "MMM d, HH:mm:ss")],
                                ["route", d.route ?? "—"],
                                ["status", d.status],
                                ["time", root.formatMs(d.ms)],
                                ["cost", root.formatCost(d.cost)],
                                ["tokens", d.tokens.toLocaleString()],
                            ];
                            for (const m of usage?.models ?? [])
                                items.push([m.model, m.calls + "× · " + (m.input + m.output).toLocaleString() + " tok" + (m.cost ? " · " + root.formatCost(m.cost) : "")]);
                            for (const [name, n] of Object.entries(usage?.tools ?? {}))
                                items.push([name, n + "×"]);
                            return items;
                        }

                        delegate: Column {
                            required property var modelData
                            Text {
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.textDim
                                text: modelData[0]
                            }
                            Text {
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: modelData[0] === "status" ? root.statusColor(modelData[1]) : modelData[0] === "id" ? Theme.accent : Theme.textSecondary
                                text: modelData[1]
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.separator
                }

                ListView {
                    id: stepsView

                    Layout.fillWidth: true
                    implicitHeight: Math.min(contentHeight, 560)
                    clip: true
                    spacing: Theme.spacingS
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.steps(root.detail)

                    Keys.onEscapePressed: root.back()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) {
                            root.back();
                            event.accepted = true;
                        }
                    }
                    Keys.onDownPressed: flick(0, -1200)
                    Keys.onUpPressed: flick(0, 1200)

                    delegate: MouseArea {
                        id: step

                        required property var modelData
                        property bool expanded: false

                        width: ListView.view.width
                        height: stepRow.implicitHeight
                        cursorShape: modelData.collapsible ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (modelData.collapsible) step.expanded = !step.expanded

                        RowLayout {
                            id: stepRow
                            width: parent.width
                            spacing: Theme.spacingM

                            Text {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: 60
                                horizontalAlignment: Text.AlignRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.textDim
                                text: step.modelData.at
                            }

                            Text {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: 72
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: step.modelData.color
                                elide: Text.ElideRight
                                text: step.modelData.label
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: stepText.implicitHeight + (step.modelData.mono ? 12 : 0) + (shot.visible ? shot.height + Theme.spacingS : 0)
                                radius: 6
                                color: step.modelData.mono ? Theme.alpha(Theme.text, 0.04) : "transparent"

                                Text {
                                    id: stepText
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: step.modelData.mono ? 6 : 0
                                    anchors.leftMargin: step.modelData.mono ? 8 : 0
                                    anchors.rightMargin: step.modelData.mono ? 8 : 0
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - (step.modelData.mono ? 1 : 0)
                                    color: step.modelData.label === "answer" ? Theme.textPrimary : Theme.textSecondary
                                    wrapMode: step.modelData.mono ? Text.WrapAnywhere : Text.Wrap
                                    maximumLineCount: step.modelData.collapsible && !step.expanded ? (step.modelData.lines ?? 6) : 100000
                                    elide: Text.ElideRight
                                    text: step.modelData.text
                                }

                                Image {
                                    id: shot
                                    anchors.top: stepText.bottom
                                    anchors.topMargin: Theme.spacingS
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: sourceSize.width > 0 ? width * sourceSize.height / sourceSize.width : 0
                                    visible: step.expanded && !!step.modelData.image
                                    source: visible ? step.modelData.image : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
                text: root.detail === null
                    ? "Enter or click to open · type !id in a prompt to reuse one · costs are estimates (prices.yaml) · Esc to close"
                    : "Click output to expand · Backspace or Esc to go back"
            }
        }
    }
}
