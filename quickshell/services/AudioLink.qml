pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// Links an MPRIS player to the PipeWire stream it is actually playing through.
//
// Chrome ignores MPRIS volume, so the only way to change a player's level is
// to move its stream. The link is by process: Chrome's MPRIS bus name is
// `chromium.instance<browser pid>`, while its stream reports the pid of the
// audio-service child — so a stream belongs to a player when the stream's
// parent pid is the player's instance id.
Singleton {
    id: root

    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio && n.type === PwNodeType.AudioOutStream)

    // stream pid -> parent pid
    property var parents: ({})

    readonly property var streamPids: {
        const pids = [];
        for (const s of root.streams) {
            const pid = s.properties["application.process.id"];
            if (pid && !pids.includes(pid))
                pids.push(pid);
        }
        return pids;
    }

    onStreamPidsChanged: {
        if (root.streamPids.length === 0) {
            root.parents = ({});
            return;
        }
        // One shell call resolves every stream's parent at once.
        const list = root.streamPids.join(" ");
        proc.command = ["sh", "-c", "for p in " + list + "; do printf '%s %s\\n' \"$p\" \"$(awk '/^PPid:/{print $2}' /proc/$p/status 2>/dev/null)\"; done"];
        proc.running = true;
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.split("\n")) {
                    const [pid, ppid] = line.trim().split(/\s+/);
                    if (pid && ppid)
                        map[pid] = ppid;
                }
                root.parents = map;
            }
        }
    }

    // The pid encoded in an MPRIS bus name, e.g. chromium.instance1953.
    function playerPid(player) {
        const m = (player?.dbusName ?? "").match(/instance(\d+)/);
        return m ? m[1] : "";
    }

    function streamFor(player) {
        if (!player)
            return null;

        const pid = root.playerPid(player);
        if (pid) {
            for (const s of root.streams) {
                const spid = String(s.properties["application.process.id"] ?? "");
                if (spid === pid || root.parents[spid] === pid)
                    return s;
            }
            // The player named a process, so a name match would just pick some
            // other tab's stream. Better to show no slider than the wrong one.
            return null;
        }

        // Players that do not encode a pid (mpv, Spotify): match on name.
        const identity = (player.identity ?? "").toLowerCase();
        if (identity !== "") {
            for (const s of root.streams) {
                const app = String(s.properties["application.name"] ?? "").toLowerCase();
                if (app && (app.includes(identity) || identity.includes(app)))
                    return s;
            }
        }

        return null;
    }
}
