//@ pragma UseQApplication
import Quickshell
import QtQuick

// greetd greeter. Runs as the `greeter` user out of /etc/greetd/quickshell-greeter,
// so it may not reference anything under /home — see Palette.qml.
ShellRoot {
    Variants {
        model: Quickshell.screens

        Greeter {
            required property var modelData
            screen: modelData
            // Only one screen may hold the keyboard; the rest are wallpaper + clock.
            primary: modelData === Quickshell.screens[0]
        }
    }
}
