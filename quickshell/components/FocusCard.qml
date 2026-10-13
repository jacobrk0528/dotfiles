import ".."
import "../services"

ControlOption {
    label: "Focus"
    glyph: Notifs.focusGlyph
    subtitle: Notifs.focusLabel
    accented: Notifs.focusMode !== ""
    accentColor: Theme.purple
    onActivated: Notifs.toggleFocus()
}
