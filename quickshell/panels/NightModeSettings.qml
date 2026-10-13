import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

ControlSettingsPane {
    id: root
    title: "Night mode"
    property int warmth: 2500
    property string validationError: ""

    Component.onCompleted: {
        warmth = NightMode.temperature;
        startInput.text = NightMode.start;
        endInput.text = NightMode.end;
        NightMode.request(["snapshot"]);
    }

    // Flush the final drag position before the shared pane unloads.
    Component.onDestruction: {
        if (adjust.running)
            NightMode.request(["set", String(warmth)]);
    }

    function saveSchedule(enabled) {
        const valid = /^([01]\d|2[0-3]):[0-5]\d$/;
        if (!valid.test(startInput.text) || !valid.test(endInput.text) || startInput.text === endInput.text) {
            validationError = "Enter different start and end times in HH:MM format.";
            return;
        }
        validationError = "";
        NightMode.saveSchedule(enabled, startInput.text, endInput.text);
    }

    Timer {
        id: adjust
        interval: 60
        onTriggered: NightMode.request(["set", String(root.warmth)])
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Blue-light filter"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textSecondary
        }
        TextButton {
            label: NightMode.enabled ? "On" : "Off"
            accented: NightMode.enabled
            accentColor: Theme.orange
            onClicked: NightMode.request(["toggle"])
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingS
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Temperature"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textSecondary
            }
            Text {
                text: root.warmth + "K"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.orange
            }
        }
        Slider {
            Layout.fillWidth: true
            value: (root.warmth - 1000) / 5500
            fillColor: Theme.orange
            onMoved: value => {
                root.warmth = Math.round((1000 + value * 5500) / 100) * 100;
                adjust.restart();
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Warmer"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
            }
            Text {
                text: "Cooler"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                color: Theme.textDim
            }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.separator }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Schedule"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
        }
        TextButton {
            label: NightMode.scheduleEnabled ? "On" : "Off"
            accented: NightMode.scheduleEnabled
            onClicked: root.saveSchedule(!NightMode.scheduleEnabled)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingM
        Text {
            text: "On at"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textSecondary
        }
        Rectangle {
            implicitWidth: 76; implicitHeight: 32; radius: 6
            color: Theme.hoverBg
            border.color: startInput.activeFocus ? Theme.accent : Theme.pillBorder
            TextInput {
                id: startInput
                anchors.centerIn: parent
                width: 56
                horizontalAlignment: TextInput.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textPrimary
                selectByMouse: true
                maximumLength: 5
                onEditingFinished: root.saveSchedule(NightMode.scheduleEnabled)
            }
        }
        Item { Layout.fillWidth: true }
        Text {
            text: "Off at"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textSecondary
        }
        Rectangle {
            implicitWidth: 76; implicitHeight: 32; radius: 6
            color: Theme.hoverBg
            border.color: endInput.activeFocus ? Theme.accent : Theme.pillBorder
            TextInput {
                id: endInput
                anchors.centerIn: parent
                width: 56
                horizontalAlignment: TextInput.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textPrimary
                selectByMouse: true
                maximumLength: 5
                onEditingFinished: root.saveSchedule(NightMode.scheduleEnabled)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "24-hour local time · Saved automatically\nStarts off at login. Manual toggles last until the next scheduled change."
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        color: Theme.textDim
    }
    Text {
        Layout.fillWidth: true
        visible: root.validationError !== "" || NightMode.error !== ""
        text: root.validationError || NightMode.error
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        color: Theme.red
    }
}
