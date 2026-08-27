import QtQuick
import ".."
import "../components"
import "../services"

// Bell with unread count; opens the notification center.
BarModule {
    alwaysVisible: true

    icon: Notifs.doNotDisturb ? "󰂛" : Notifs.count > 0 ? "󰂚" : "󰂜"
    text: Notifs.count > 0 ? String(Notifs.count) : ""

    textColor: Notifs.doNotDisturb ? Theme.orange : Notifs.count > 0 ? Theme.accent : Theme.textSecondary

    tooltipText: {
        if (Notifs.doNotDisturb)
            return "Do not disturb";
        if (Notifs.count === 0)
            return "No notifications";
        return Notifs.count + " notification" + (Notifs.count === 1 ? "" : "s");
    }

    onLeftClicked: Panels.toggle("notifications")
    onRightClicked: Notifs.doNotDisturb = !Notifs.doNotDisturb
}
