import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import ".."
import "../components"
import "../services"

// Live PipeWire binding — no polling, updates instantly on volume change.
BarModule {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    icon: ""
    text: {
        if (!sink)
            return "";
        if (muted)
            return "󰖁 muted";
        const pct = Math.round(volume * 100);
        const ico = pct < 34 ? "󰕿" : pct < 67 ? "󰖀" : "󰕾";
        return ico + " " + pct + "%";
    }

    tooltipText: sink?.description ?? ""

    onLeftClicked: Panels.toggle("control")
    onRightClicked: {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    onScrolled: delta => {
        if (!sink?.audio)
            return;
        const step = delta > 0 ? 0.05 : -0.05;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + step));
    }
}
