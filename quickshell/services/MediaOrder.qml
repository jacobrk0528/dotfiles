pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// MPRIS players in the order they first appeared.
//
// The desktop cards used to be sorted by isPlaying, which meant the whole stack
// shuffled the moment something was paused — and the play button slid out from
// under the cursor. Pinning the order instead keeps a card where it appeared.
Singleton {
    id: root

    // dbusNames, first-seen first. Names that no longer resolve to a player are
    // dropped: an app that restarts comes back under a new bus name, so keeping
    // the dead ones would grow this list without bound.
    property var order: []

    // playerctld proxies whichever player is currently active, so it shows up
    // as a second bus name mirroring a real player — a phantom duplicate card.
    // Anything that enumerates players should go through here.
    function isProxy(dbusName) {
        return dbusName.endsWith(".playerctld");
    }

    readonly property var players: {
        const byName = {};
        for (const p of Mpris.players.values)
            if (!root.isProxy(p.dbusName))
                byName[p.dbusName] = p;
        return root.order.map(n => byName[n]).filter(p => p !== undefined);
    }

    function sync() {
        // Mpris can briefly report the same bus name twice while a player
        // re-registers. Deduplicating only against `kept` would let that pair
        // through and pin a permanent duplicate card, so dedupe within the
        // live list too.
        const live = [];
        for (const p of Mpris.players.values)
            if (p.dbusName && !root.isProxy(p.dbusName) && !live.includes(p.dbusName))
                live.push(p.dbusName);

        const kept = [];
        for (const n of root.order)
            if (live.includes(n) && !kept.includes(n))
                kept.push(n);

        const next = kept.concat(live.filter(n => !kept.includes(n)));

        // Only assigns on a real change, so the write cannot feed back through
        // `players` into another sync.
        if (next.length !== root.order.length || next.some((n, i) => n !== root.order[i]))
            root.order = next;
    }

    Component.onCompleted: root.sync()

    Connections {
        target: Mpris.players

        function onValuesChanged() {
            root.sync();
        }
    }
}
