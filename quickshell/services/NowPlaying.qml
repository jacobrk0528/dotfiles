pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Raises a transient "now playing" OSD when a track actually changes.
//
// Deliberately not routed through Notifs: a song change is an OSD, not
// something that belongs in the notification history.
Singleton {
    id: root

    property bool active: false
    property string title: ""
    property string artist: ""
    property string artUrl: ""
    property string identity: ""

    // Ignore the initial binding evaluation so nothing pops on shell reload.
    property bool ready: false

    readonly property real maxTrackLength: 20 * 60

    // A Twitch stream rewrites its title whenever the broadcaster edits it, and
    // a live radio has no length at all — neither is a track start. Chrome
    // reports ~6h for a stream and a few minutes for a song, so length is the
    // discriminator; a player that also advertises a playlist is a real media
    // session, so a long mix inside one is still announced.
    function isStream(p) {
        if (p.canGoNext || p.canGoPrevious)
            return false;
        return !p.lengthSupported || p.length <= 0 || p.length > root.maxTrackLength;
    }

    function key(p) {
        return p.trackTitle + " " + p.trackArtist;
    }

    function announce(p) {
        root.title = p.trackTitle;
        root.artist = p.trackArtist;
        root.artUrl = p.trackArtUrl;
        root.identity = p.identity;
        root.active = true;
        // Restart rather than queue: skipping through tracks replaces content.
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 4000
        onTriggered: root.active = false
    }

    Timer {
        interval: 800
        running: true
        onTriggered: root.ready = true
    }

    // One watcher per player, so a change in one is never attributed to another.
    Instantiator {
        model: MediaOrder.players

        delegate: QtObject {
            id: watcher

            required property MprisPlayer modelData

            // Last track this player was seen on, announced or not. Recorded
            // even when suppressed so a later resume cannot fire on it.
            property string seen: ""

            function settle() {
                const p = watcher.modelData;
                if (!p || p.trackTitle === "")
                    return;
                const k = root.key(p);
                if (k === watcher.seen)
                    return;
                watcher.seen = k;
                if (root.ready && p.isPlaying && !root.isStream(p))
                    root.announce(p);
            }

            // Metadata fields land one property at a time, so wait for the
            // burst to settle before deciding anything.
            property Timer debounce: Timer {
                interval: 250
                onTriggered: watcher.settle()
            }

            property Connections conn: Connections {
                target: watcher.modelData

                // uniqueId covers players that repeat a title; the text signals
                // cover the ones that never change trackid. Position is never
                // watched — it ticks constantly and means nothing here.
                function onUniqueIdChanged() {
                    watcher.debounce.restart();
                }
                function onTrackTitleChanged() {
                    watcher.debounce.restart();
                }
                function onTrackArtistChanged() {
                    watcher.debounce.restart();
                }
                function onIsPlayingChanged() {
                    watcher.debounce.restart();
                }
            }

            // Seed from whatever is already playing: a shell reload must not
            // re-announce the current track.
            Component.onCompleted: {
                if (watcher.modelData?.trackTitle)
                    watcher.seen = root.key(watcher.modelData);
                watcher.debounce.restart();
            }
        }
    }
}
