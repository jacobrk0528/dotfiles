pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// Owns the org.freedesktop.Notifications server (replaces mako).
//
// Two views over the same notifications:
//   popups  — transient, auto-expire, shown as floating cards
//   all     — everything still tracked, shown in the notification center
// A notification leaving the popup list stays in the center until dismissed.
// Blocked apps (by appName) are dropped entirely — no popup, no center entry.
// Priority apps bypass Do Not Disturb and still pop up while DND is on.
Singleton {
    id: root

    property bool doNotDisturb: false
    property var popups: []

    readonly property var all: server.trackedNotifications.values
    readonly property int count: all.length
    readonly property var blockedApps: adapter.blockedApps
    readonly property var priorityApps: adapter.priorityApps

    // KDE Connect forwards every phone notification under the one appName
    // "KDE Connect", with the phone-side app's own name only showing up in
    // summary — so blocking "KDE Connect" silences the phone entirely.
    // Key on "KDE Connect: <summary>" instead so e.g. forwarded Slack pings
    // can be blocked without touching forwarded SMS, or the native desktop
    // Slack app (which reports its own real appName).
    function appKey(appName, summary) {
        if (appName === "KDE Connect" && summary)
            return "KDE Connect: " + summary;
        return appName;
    }

    function isBlocked(appName) {
        return root.blockedApps.includes(appName);
    }

    function isPriority(appName) {
        return root.priorityApps.includes(appName);
    }

    // KDE Connect forwards Android notifications (e.g. GroupMe's bolded-name
    // style) with their HTML markup entity-escaped rather than raw, so
    // "<b>Name</b><br/>text" arrives as "&lt;b&gt;Name&lt;/b&gt;&lt;br/&gt;text".
    // Decode it once so Text.StyledText renders the real tags instead of
    // showing them literally.
    function decodeBody(body) {
        if (!body)
            return body;
        return body
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&#39;|&apos;/g, "'")
            .replace(/&amp;/g, "&");
    }

    function blockApp(appName) {
        if (!appName || root.isBlocked(appName))
            return;
        adapter.priorityApps = adapter.priorityApps.filter(a => a !== appName);
        adapter.blockedApps = adapter.blockedApps.concat([appName]);
    }

    function unblockApp(appName) {
        adapter.blockedApps = adapter.blockedApps.filter(a => a !== appName);
    }

    function markPriority(appName) {
        if (!appName || root.isPriority(appName))
            return;
        adapter.blockedApps = adapter.blockedApps.filter(a => a !== appName);
        adapter.priorityApps = adapter.priorityApps.concat([appName]);
    }

    function unmarkPriority(appName) {
        adapter.priorityApps = adapter.priorityApps.filter(a => a !== appName);
    }

    FileView {
        id: blocklistFile
        path: Quickshell.env("HOME") + "/dotfiles/quickshell/notif-blocklist.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter
            property list<string> blockedApps: []
            property list<string> priorityApps: []
        }
    }

    // Permanent notification log, independent of the live/tracked list above —
    // entries stick around after a notification is dismissed or "Clear" is hit,
    // so they can be reviewed and marked later from the history tab.
    // Plain-text JSON (not JsonAdapter) since entries are free-form objects,
    // not a fixed set of named properties.
    property var history: []
    property bool historyLoaded: false

    function nextHistoryId() {
        return Date.now() + "-" + Math.random().toString(36).slice(2, 8);
    }

    function loadHistory() {
        const text = historyFile.text();
        if (!text || text.trim() === "") {
            root.history = [];
        } else {
            try {
                root.history = JSON.parse(text);
            } catch (e) {
                console.warn("Notifs: failed to parse history file, starting fresh:", e);
                root.history = [];
            }
        }
        root.historyLoaded = true;
    }

    function saveHistory() {
        historyFile.setText(JSON.stringify(root.history, null, 2));
    }

    function appendHistory(notif) {
        const entry = {
            id: root.nextHistoryId(),
            appName: notif.appName ?? "",
            summary: notif.summary ?? "",
            body: notif.body ?? "",
            urgency: notif.urgency,
            timestamp: Date.now(),
            marked: false
        };
        root.history = root.history.concat([entry]);
        root.saveHistory();
    }

    function toggleHistoryMark(id) {
        root.history = root.history.map(e => e.id === id ? Object.assign({}, e, {
            marked: !e.marked
        }) : e);
        root.saveHistory();
    }

    function removeHistoryEntry(id) {
        root.history = root.history.filter(e => e.id !== id);
        root.saveHistory();
    }

    function clearHistory() {
        root.history = [];
        root.saveHistory();
    }

    FileView {
        id: historyFile
        path: Quickshell.env("HOME") + "/dotfiles/quickshell/notif-history.json"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: root.loadHistory()
        onLoadFailed: error => root.loadHistory()
        onFileChanged: reload()
    }

    readonly property int defaultTimeout: 5000
    readonly property int criticalTimeout: 10000

    // How long a popup may stay on screen. The sender's request is only an
    // upper bound — our own timeout is a hard ceiling it can lower but never
    // raise. notif.expireTimeout is already in milliseconds (freedesktop
    // expire_timeout, straight off the wire); -1 means "server decides" and
    // 0 means "never expire", both of which fall through to the ceiling.
    function timeoutFor(notif) {
        const ceiling = notif.urgency === NotificationUrgency.Critical ? root.criticalTimeout : root.defaultTimeout;
        if (notif.expireTimeout > 0)
            return Math.min(notif.expireTimeout, ceiling);
        return ceiling;
    }

    // Hide the floating card but keep the entry in the center.
    function dismissPopup(notif) {
        root.popups = root.popups.filter(n => n !== notif);
    }

    function clearPopups() {
        root.popups = [];
    }

    // Remove entirely — from popups and the center.
    function close(notif) {
        root.dismissPopup(notif);
        notif.dismiss();
    }

    function clearAll() {
        root.clearPopups();
        for (const n of root.all.slice())
            n.dismiss();
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        actionIconsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        inlineReplySupported: true

        onNotification: notif => {
            const key = root.appKey(notif.appName, notif.summary);
            if (root.isBlocked(key))
                return;

            notif.tracked = true;
            root.appendHistory(notif);

            if (!root.doNotDisturb || root.isPriority(key))
                root.popups = [notif].concat(root.popups);

            notif.closed.connect(() => root.dismissPopup(notif));
        }
    }
}
