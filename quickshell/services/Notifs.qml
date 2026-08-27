pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Owns the org.freedesktop.Notifications server (replaces mako).
//
// Two views over the same notifications:
//   popups  — transient, auto-expire, shown as floating cards
//   all     — everything still tracked, shown in the notification center
// A notification leaving the popup list stays in the center until dismissed.
Singleton {
    id: root

    property bool doNotDisturb: false
    property var popups: []

    readonly property var all: server.trackedNotifications.values
    readonly property int count: all.length

    readonly property int defaultTimeout: 3000
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

        onNotification: notif => {
            notif.tracked = true;

            if (!root.doNotDisturb)
                root.popups = [notif].concat(root.popups);

            notif.closed.connect(() => root.dismissPopup(notif));
        }
    }
}
