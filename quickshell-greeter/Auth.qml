pragma Singleton
import Quickshell
import Quickshell.Services.Greetd
import QtQuick

// greetd conversation, reduced to the four states the UI cares about:
// idle, busy, failed, launching.
//
// GREETER_DEMO=1 replaces greetd with a fake conversation so the UI can be
// exercised (and screenshotted) inside a nested compositor. It is opt-in
// rather than an automatic fallback: silently showing a login prompt that
// authenticates nothing would be worse than showing an error.
Singleton {
    id: root

    readonly property bool demo: Quickshell.env("GREETER_DEMO") === "1"

    property string user: "jkrebs"
    property string message: ""
    property bool failed: false
    property bool busy: false
    property bool launching: false

    readonly property var sessions: [
        {
            name: "Hyprland (uwsm)",
            // The resolved Exec= of hyprland-uwsm.desktop. Going through uwsm
            // is what gives the session its systemd units and environment; a
            // bare `Hyprland` here would silently produce a different session
            // to the one started from the TTY today.
            command: ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"]
        },
        {
            name: "Hyprland (bare)",
            command: ["Hyprland"]
        }
    ]

    property int sessionIndex: 0
    readonly property var session: sessions[sessionIndex]

    property string pending: ""

    function cycleSession() {
        sessionIndex = (sessionIndex + 1) % sessions.length;
    }

    function submit(password) {
        if (busy || launching)
            return;

        busy = true;
        failed = false;
        message = "";
        pending = password;

        if (demo) {
            demoTimer.restart();
            return;
        }

        if (!Greetd.available) {
            fail("greetd is not available");
            return;
        }

        if (Greetd.state === GreetdState.Inactive)
            Greetd.createSession(root.user);
        else
            Greetd.respond(password);
    }

    function clearFailure() {
        failed = false;
        message = "";
    }

    function fail(msg) {
        busy = false;
        launching = false;
        failed = true;
        message = msg && msg.length ? msg : "Authentication failed";
        pending = "";

        if (!demo && Greetd.available && Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
    }

    function launch() {
        launching = true;
        message = "Starting session…";
        Greetd.launch(root.session.command, ["XDG_SESSION_TYPE=wayland"], true);
    }

    Connections {
        target: root.demo ? null : Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired)
                Greetd.respond(root.pending);
            else if (error)
                root.message = message;
        }

        function onAuthFailure(message) {
            root.fail(message);
        }

        function onReadyToLaunch() {
            root.launch();
        }

        function onError(error) {
            root.fail(error);
        }
    }

    Timer {
        id: demoTimer
        interval: 700

        onTriggered: {
            if (root.pending === "demo") {
                root.busy = false;
                root.launching = true;
                root.message = "Starting session…";
            } else {
                root.fail("Authentication failed");
            }
        }
    }
}
