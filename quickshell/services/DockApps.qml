pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// State behind the bottom dock (dock/Dock.qml): pinned apps, running apps
// grouped by window class, and windows parked on special:minimized.
//
// Pins and the drag-and-drop order live in dock.json, keyed by desktop entry
// id (the .desktop file name). Running apps with no desktop entry fall back to
// their window class as the key.
Singleton {
    id: root

    FileView {
        path: Quickshell.env("HOME") + "/dotfiles/quickshell/dock.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: cfg
            property list<string> pins: []
            // Keys in the order last dragged; anything not listed keeps its
            // pins-then-running position after these.
            property list<string> order: []
            // Per window class overrides: { class: { name, icon, exec, app } }.
            //  icon: theme icon name or a path (~/ allowed)
            //  exec: shell command that launches it, which also makes the
            //        class itself pinnable (e.g. yazi's own ghostty window)
            //  app:  key to group its windows under instead (another pin)
            property var classes: ({})
        }
    }

    readonly property var pins: cfg.pins

    // ── Windows ──────────────────────────────────────────────────
    // lastIpcObject only updates on a manual refresh, not automatically as
    // windows move — see the same note in services/WindowLink.qml.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            Hyprland.refreshToplevels();
            Hyprland.refreshMonitors();
        }
    }

    // Plain IPC client objects, most recently focused first.
    readonly property var clients: Hyprland.toplevels.values
        .map(t => t.lastIpcObject)
        .filter(c => c && c.address && c["class"])
        .sort((a, b) => a.focusHistoryID - b.focusHistoryID)

    readonly property var minimized: clients.filter(c => isMinimized(c))

    readonly property string focusedAddress: clients.length > 0 && clients[0].focusHistoryID === 0 ? clients[0].address : ""

    function isMinimized(c) {
        return String(c.workspace?.name ?? "") === "special:minimized";
    }

    // ── Desktop entries ──────────────────────────────────────────
    function entryFor(cls) {
        return DesktopEntries.byId(cls) ?? DesktopEntries.heuristicLookup(cls);
    }

    // The dock key a window belongs to, and the entry behind it. Classes
    // configured in dock.json are taken as-is so a heuristic match can't
    // split them off from their pin.
    function keyFor(cls) {
        const custom = cfg.classes[cls];
        if (custom)
            return custom.app ?? cls;
        return root.entryFor(cls)?.id ?? cls;
    }

    function nameFor(entry, cls) {
        return cfg.classes[cls]?.name ?? entry?.name ?? cls;
    }

    // "" when nothing matches; AppIcon then draws a letter tile.
    function iconFor(entry, cls) {
        const custom = String(cfg.classes[cls]?.icon ?? "");
        if (custom.startsWith("~/"))
            return "file://" + Quickshell.env("HOME") + custom.slice(1);
        if (custom.startsWith("/"))
            return "file://" + custom;
        // com.jkrebs.btop → btop
        return Quickshell.iconPath(custom, true)
            || Quickshell.iconPath(entry?.icon ?? "", true)
            || Quickshell.iconPath(cls, true)
            || Quickshell.iconPath(cls.split(".").pop(), true);
    }

    // ── Apps ─────────────────────────────────────────────────────
    // [{ key, name, icon, entry, exec, pinned, windows, focused }]
    readonly property var apps: {
        const byKey = {};
        const list = [];

        function add(key, entry, cls, pinned) {
            const app = {
                key: key,
                entry: entry,
                exec: String(cfg.classes[key]?.exec ?? ""),
                name: root.nameFor(entry, cls),
                icon: root.iconFor(entry, cls),
                pinned: pinned,
                windows: [],
                focused: false
            };
            byKey[key] = app;
            list.push(app);
            return app;
        }

        for (const id of cfg.pins) {
            const entry = DesktopEntries.byId(id);
            if (!byKey[id] && (entry || cfg.classes[id]?.exec))
                add(id, entry, id, true);
        }

        for (const c of root.clients) {
            const key = root.keyFor(c["class"]);
            const app = byKey[key] ?? add(key, DesktopEntries.byId(key) ?? root.entryFor(key), key, false);
            app.windows.push(c);
            if (c.address === root.focusedAddress)
                app.focused = true;
        }

        const rank = {};
        cfg.order.forEach((k, i) => {
            if (rank[k] === undefined)
                rank[k] = i;
        });
        return list
            .map((app, i) => ({ app: app, i: i }))
            .sort((a, b) => ((rank[a.app.key] ?? 1e9) - (rank[b.app.key] ?? 1e9)) || (a.i - b.i))
            .map(x => x.app);
    }

    readonly property var byKey: {
        const m = {};
        for (const app of root.apps)
            m[app.key] = app;
        return m;
    }

    // ── Actions ──────────────────────────────────────────────────
    function launch(app) {
        if (app?.exec)
            Quickshell.execDetached(["sh", "-c", app.exec.replace(/^~\//, Quickshell.env("HOME") + "/")]);
        else
            app?.entry?.execute();
    }

    // Dock click: launch it, bring it back, or cycle through its windows.
    function activate(app) {
        const open = app.windows.filter(c => !root.isMinimized(c));
        if (open.length === 0) {
            if (app.windows.length > 0)
                root.restore(app.windows[0]);
            else
                root.launch(app);
            return;
        }
        // Already focused: step to its least recently used window instead
        root.focusWindow(app.focused && open.length > 1 ? open[open.length - 1] : open[0]);
    }

    // Run dispatchers with cursor warping off, so a click on the dock leaves
    // the mouse where it is. Warping stays on for everything else (SUPER
    // keybinds jump to the window as usual): the flag is set and restored
    // inside one Lua call, around just these dispatchers.
    function dispatchNoWarp(dispatchers) {
        Hyprland.dispatch("function() hl.config({ cursor = { no_warps = true } }); "
            + dispatchers.map(d => "hl.dispatch(" + d + "); ").join("")
            + "hl.config({ cursor = { no_warps = false } }) end");
    }

    function focusWindow(c) {
        if (root.isMinimized(c)) {
            root.restore(c);
            return;
        }
        const ws = String(c.workspace?.name ?? "");
        // A hidden scratchpad (slack/logs/media) has to be toggled into view;
        // focusing the window alone would not show it.
        const steps = [];
        if (ws.startsWith("special:") && !root.specialShown(ws))
            steps.push('hl.dsp.workspace.toggle_special("' + ws.slice("special:".length) + '")');
        steps.push('hl.dsp.focus({ window = "address:' + c.address + '" })');
        root.dispatchNoWarp(steps);
    }

    function specialShown(name) {
        return Hyprland.monitors.values.some(m => m.lastIpcObject?.specialWorkspace?.name === name);
    }

    // Minimized windows come back onto the workspace in front of you.
    function restore(c) {
        const ws = Hyprland.focusedMonitor?.activeWorkspace?.id;
        if (ws === undefined)
            return;
        root.dispatchNoWarp([
            'hl.dsp.window.move({ workspace = ' + ws + ', window = "address:' + c.address + '" })',
            'hl.dsp.focus({ window = "address:' + c.address + '" })'
        ]);
    }

    function close(c) {
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + c.address + '" })');
    }

    function setPinned(app, pinned) {
        const rest = cfg.pins.filter(k => k !== app.key);
        cfg.pins = pinned ? rest.concat([app.key]) : rest;
    }

    // Save the order currently shown, keeping any keys that aren't on the
    // dock right now (a quit app) after them so they aren't forgotten.
    function saveOrder(visible) {
        cfg.order = visible.concat(cfg.order.filter(k => !visible.includes(k)));
    }
}
