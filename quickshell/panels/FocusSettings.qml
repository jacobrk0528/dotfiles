pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

ControlSettingsPane {
    id: root
    title: "Focus modes"
    property string selected: Notifs.focusMode || Notifs.lastFocusMode
    readonly property var categories: [
        { key: "song", label: "New song" },
        { key: "slack", label: "Slack" },
        { key: "messages", label: "Messages" },
        { key: "groupme", label: "GroupMe" },
        { key: "phone", label: "Phone" },
        { key: "system", label: "System notifications" }
    ]

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Current mode: " + Notifs.focusLabel
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textSecondary
        }
        TextButton {
            label: Notifs.focusMode !== "" ? "Turn off" : "Turn on"
            accented: Notifs.focusMode !== ""
            accentColor: Theme.purple
            onClicked: Notifs.setFocus(Notifs.focusMode !== "" ? "" : root.selected)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingS
        Repeater {
            model: Notifs.focusModes
            TextButton {
                required property var modelData
                Layout.fillWidth: true
                label: modelData.label
                accented: root.selected === modelData.key
                accentColor: Theme.purple
                onClicked: {
                    root.selected = modelData.key;
                    Notifs.setFocus(modelData.key);
                }
            }
        }
    }

    Text {
        text: "Allowed in " + (Notifs.focusModes.find(m => m.key === root.selected)?.label ?? "")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.textPrimary
    }

    Repeater {
        model: root.categories
        RowLayout {
            id: ruleRow
            required property var modelData
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: ruleRow.modelData.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textSecondary
            }
            TextButton {
                label: Notifs.modeAllows(root.selected, ruleRow.modelData.key) ? "Allowed" : "Silenced"
                accented: Notifs.modeAllows(root.selected, ruleRow.modelData.key)
                accentColor: Theme.purple
                onClicked: Notifs.setModeRule(root.selected, ruleRow.modelData.key, !Notifs.modeAllows(root.selected, ruleRow.modelData.key))
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "Phone allows all KDE Connect notifications. Messages and GroupMe can be allowed separately when Phone is off. System notifications covers screenshots, dictation, night mode, and process watch. Blocked apps stay blocked. Silenced notifications remain in the center. Changes save automatically."
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        color: Theme.textDim
    }
}
