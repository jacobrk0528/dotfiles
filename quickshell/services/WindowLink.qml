pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Links an MPRIS player to the Hyprland window it is playing in.
//
// Chrome's MPRIS bus name is `chromium.instance<browser pid>`, and Hyprland
// reports a pid per client, so pid is the link — reliable for a player that
// owns its browser process (YouTube Music runs under its own --user-data-dir).
// A browser shared by many tabs publishes one player for all of its windows,
// so the track title breaks the tie when it can.
Singleton {
    id: root

    // Player awaiting a window lookup, held while the toplevel list refreshes.
    property var pending: null

    // The pid encoded in an MPRIS bus name, e.g. chromium.instance1953.
    function playerPid(player) {
        const m = (player?.dbusName ?? "").match(/instance(\d+)/);
        return m ? m[1] : "";
    }

    function windowFor(player) {
        if (!player)
            return null;

        const pid = root.playerPid(player);
        const title = (player.trackTitle ?? "").toLowerCase();
        const identity = (player.identity ?? "").toLowerCase();
        let fallback = null;

        for (const t of Hyprland.toplevels.values) {
            const obj = t.lastIpcObject;
            if (!obj)
                continue;

            if (pid) {
                if (String(obj.pid) !== pid)
                    continue;
                const wtitle = String(obj.title ?? "").toLowerCase();
                if (title !== "" && wtitle.includes(title))
                    return t;
                if (!fallback)
                    fallback = t;
                continue;
            }

            // Players that do not encode a pid (mpv, Spotify): match on name.
            if (!fallback && identity !== "") {
                const cls = String(obj["class"] ?? "").toLowerCase();
                if (cls && (cls.includes(identity) || identity.includes(cls)))
                    fallback = t;
            }
        }

        return fallback;
    }

    // Bring a player's window to the user: a window parked on a special
    // workspace toggles that scratchpad (so a second click hides it again),
    // anything else just gets focused where it lives.
    function summon(player) {
        const t = root.windowFor(player);
        if (!t)
            return;

        const ws = String(t.lastIpcObject?.workspace?.name ?? "");
        if (ws.startsWith("special:"))
            Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + ws.slice("special:".length) + '")');
        else
            Hyprland.dispatch('hl.dsp.focus({ window = "address:' + t.lastIpcObject.address + '" })');
    }

    // lastIpcObject only refreshes on Hyprland events, so a window moved
    // between workspaces can be stale; re-read the list before acting on it.
    function focus(player) {
        root.pending = player;
        Hyprland.refreshToplevels();
        settle.restart();
    }

    Timer {
        id: settle

        interval: 100
        onTriggered: {
            const player = root.pending;
            root.pending = null;
            root.summon(player);
        }
    }
}
