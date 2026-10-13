# Desktop shell

A custom [quickshell](https://quickshell.org) desktop built for this machine. Replaces waybar,
mako, and the rofi/wofi helper menus with one QML shell that shares state and styling.

Launched by `hypr/hyprland.lua` (`hl.exec_cmd("qs")`). Edits to any file here hot-reload
immediately — except `qmldir`, which needs `pkill qs && qs &`.

## Design language — "Slate & Frost"

Surfaces are the theme base at 75% (top bar and dock, matching Ghostty) / 94% (panels) with a 1px white-8% border, blurred by
Hyprland. Radius 10 for bar pills, 16 for panels. Type is JetBrainsMono Nerd Font. Text sits at
85% / 60% / 35% white for primary / secondary / dim. The accent is frost cyan `#8be9fd`;
green→yellow→red carry status. Motion is 150ms for hover, 200ms for panels, ease-out.

## Layout

| Path | What it holds |
| --- | --- |
| `shell.qml` | Root — wires every surface together |
| `Theme.qml` | Design tokens, read from `theme.json` (live) |
| `Shortcuts.qml` | Hyprland global shortcuts → panel state |
| `Bar.qml` | The status bar, one per monitor |
| `dock/` | The bottom app dock, one per monitor; pins in `dock.json` |
| `services/` | Singletons: `Notifs`, `Panels`, `Osd`, `SysInfo` |
| `components/` | Reusable widgets: `Pill`, `Card`, `Slider`, `BarModule`, … |
| `modules/` | Bar modules |
| `panels/` | Launcher, control center, notification center, clipboard, wallpapers, power menu, cheatsheet |
| `overlays/` | Notification popups, volume OSD |
| `desktop/` | Wallpaper-layer widgets |
| `scripts/` | Shell/Python helpers the QML calls |

Anything new in the repo root must also be listed in `qmldir`, or QML will not see it.

## Surfaces

**Bar** — workspaces (special workspaces hidden), minimized count, dictation, clock with
calendar popup, control center button, notifications, tray.
Clicking workspaces dispatches straight to the `hl.dsp.focus()` Lua dispatchers, so the old
`hypr_ipc_proxy.py` translation layer is gone.

**Dock** — a macOS-style bar along the bottom of every monitor, always visible (it reserves
its height the way the top bar does). Now playing sits on the left and system stats (CPU, memory, GPU util/temp, CPU temp, disk) on
the right; the middle holds pinned apps,
then any other running app, then — after a divider — every window parked on `special:minimized`.
Running apps are grouped by window class and matched to a desktop entry
(`services/DockApps.qml`); a dot under an icon is one open window. Left click launches, focuses,
or cycles through an app's windows (toggling its scratchpad into view if it lives on one);
middle click opens a new window; right click lists its windows plus New window / Keep in Dock /
Close. Drag an icon sideways to reorder. Right-click empty dock space for the "Add to Dock"
picker (`panels/DockPicker.qml`): every installed app in a searchable grid, click or Enter to
pin/unpin. The stat cards colour their value green / yellow / red against per-stat thresholds
set in `dock/Dock.qml`. Clicking a minimized window brings it back onto the
workspace in front of you. Pins, the dragged order, and names/icons for window classes with no
desktop entry (the tmux terminal, YouTube Music) all live in `dock.json`, which reloads live.

**Notifications** — quickshell owns `org.freedesktop.Notifications`. Popups follow the focused
monitor, carry an urgency stripe and a timeout bar, pause on hover, and support actions.
Everything stays in the center until dismissed. `SUPER+N` opens it; the bell toggles
do-not-disturb on right-click.

**Control center** (`SUPER+C`, or click the switches button in the bar) — output device and volume, output
switcher, per-app volume sliders with live peak meters, a carousel of media cards, one per MPRIS player (same
`desktop/MediaCard.qml` as the desktop widgets, so every player shows up, not just whichever
one is playing — its stream is excluded from the per-app volume list to avoid a duplicate
slider), plus a four-column grid of square Network, Bluetooth, Night mode, and Focus icon tiles.
Left-click toggles Wi-Fi, Bluetooth power, night mode, or the last focus mode; Ethernet opens its details.
Right-click opens the shared settings pane for wired status/Wi-Fi connections, paired
Bluetooth devices with battery and connect/disconnect, or night-mode preferences.
Joining an unknown Wi-Fi
network hands off to `nmtui-connect` since it needs a passphrase. Click the Night
tile to turn it on/off. Right-click it for an adjacent
settings pane with a 1000–6500K slider, schedule toggle, and editable on/off times.
The default schedule is 18:00–08:00 local time; login always starts off. Manual
overrides last until the next scheduled transition, including after suspend.
Settings persist in `~/.local/state/hypr/night-mode.json`. Quickshell checks for
transitions every 10 seconds. `SUPER+CTRL+N` still toggles the filter manually.

**Focus modes** — left-click Focus to toggle the last selected mode, or right-click
to choose DND, Work, Focus, or Personal and edit the allowed categories. Defaults:
DND allows nothing; Work allows new-song OSDs, Process watch, and Slack; Focus
allows songs and Process watch; Personal allows songs, Process watch, Messages,
and GroupMe (native or forwarded by KDE Connect), with separate switches for each.
Phone allows all KDE Connect notifications and starts disabled in every mode.
With Phone off, individual app switches can still allow forwarded notifications.
Other popups are silenced while a mode
is active, including priority apps; globally blocked apps remain blocked. Silenced
notifications still enter the notification center/history. With modes off, normal
popup behavior returns. Rules and the last/current mode persist in `focus-modes.json`.

**Extending control-center options:** use `components/ControlOption.qml` with
an `onActivated` action and a `settingsComponent` containing a
`components/ControlSettingsPane.qml` instance. The shared template supplies the
title, X button, card styling, and return navigation. The control center loads
that component to its left in the same overlay, keeping the main controls usable;
on narrow screens it places settings over the control card. X or Escape dismisses
only settings. Opening another main panel clears settings. Night mode is the
first consumer; the shared components and navigation contain no night-mode logic.

**AI quick-ask** (`SUPER+A`) — focuses `dock/JevPrompt.qml`, backed by
`~/.local/bin/artoo ask --json` (`~/dotfiles/artoo`). Questions can navigate apps on
other monitors and hidden/special workspaces, read screenshots and return an answer. The
dock records the original desktop context; information lookups return there when finished.
Reading/navigation is automatic; writing, sending, deleting and other changes require the
Run/Cancel popup. Stop cancels the task and lets it restore the desktop. Desktop input is
serialized across monitors. `SUPER+SHIFT+A` opens conversation history with steps, screenshots,
inspection checklists, approvals and cost. See artoo's README for setup and `doctor`.
The older Claude-backed `panels/Ai.qml` / `services/AiShot.qml` path remains a separate
`quickshell:ai` shortcut; `SUPER+A` uses `quickshell:jev`.

**Launcher** (`SUPER+Space` or `SUPER+D`) — fuzzy search over desktop entries, ranked by name
prefix → name substring → keywords. Arrows to move, Enter to launch.

**Clipboard** (`SUPER+V`) — searchable `cliphist` history; Enter copies, Del or middle-click
removes an entry. Replaced the `cliphist | wofi` pipeline. Copied images are titled by a
local vision model (`scripts/clip-label`, Ollama `gemma3:4b`; override with
`CLIP_LABEL_MODEL`) so screenshots are listed and searchable by what they show instead of
`[[ binary data … ]]`. Titles are cached in `~/.cache/cliphist/labels.tsv`;
`clip-label --all` backfills old entries.

**Power menu** (`SUPER+Escape`) — lock / log out / suspend / reboot / shut down.

**Cheatsheet** (`SUPER+/`) — every keybind, generated from `hyprland.lua` by `scripts/keybinds`,
so it cannot drift out of sync with the real config. Type to filter on key or action: "audio"
finds the sink switches and media keys, "super + c" finds what that chord does. Esc clears the
filter, then closes.

**Wallpapers** (`SUPER+W`) — picker over `hypr/wallpapers`, including five generated from the
palette (see below). The shell draws the wallpaper itself on its own background layer and
crossfades between them; `scripts/wallpaper` just writes `hypr/wallpaper.json`, which the
shell watches. hyprpaper is not used — 0.8.4 refuses to bind a wallpaper to any monitor on
this machine ("has no target"), and drawing it in-process removes a daemon and gets us the
crossfade. `hypr/wallpaper.conf` is generated alongside so the lock screen matches.

**Desktop widgets** — laid out across every screen: system meters top left, clock top centre,
media stack top right, AI quick-ask bottom left. Each group sits on a translucent rounded panel
(`desktop/WidgetPanel.qml`, `widgetOpacity` in `theme.json`) that Hyprland blurs, so the text
holds up over a bright wallpaper as well as a dark one; `ignore_alpha` keeps the blur on the
panels rather than the empty space between them. Only the media controls and the AI card take
clicks (and, for the AI card's input, keyboard focus — the layer uses on-demand keyboard
interactivity rather than none, so typing there doesn't require a hotkey); the rest is
click-through.

The widget layer sits on the **bottom** layer, not the background — the wallpaper owns
background, and two surfaces on the same layer stack by creation order rather than by intent,
so sharing it let the wallpaper paint over the widgets.

Each MPRIS player gets its own card — artwork, title/artist, seek bar, prev/play/next, mute
and volume — so YouTube Music, a YouTube video and a Twitch stream each get independent
controls.

**How the volume slider works.** Chrome ignores MPRIS volume outright, so the card drives the
player's PipeWire stream instead. Linking the two is by process: Chrome's bus name is
`chromium.instance<browser pid>` while its stream reports the pid of the audio-service child,
so a stream belongs to a player when the stream's parent pid is the player's instance id
(`services/AudioLink.qml`). When a player names a process but no stream matches, the card hides
the slider rather than grabbing some other tab's stream.

**Independent control per source.** Chrome publishes one MPRIS player per browser process, so
tabs sharing a browser cannot be paused or skipped separately. `SUPER+M` (`scripts/ytmusic`)
runs YouTube Music in its own Chrome instance, giving it its own MPRIS player and its own
stream — it then appears as a separate card with working transport controls. Costs a one-time
sign-in in that profile.

## Theming

`theme.json` is the single source of truth. Quickshell reads it live. For everything that
cannot read JSON, run:

```sh
quickshell/scripts/apply-theme
```

That regenerates `hypr/colors.lua`, `hypr/colors.conf`, `hypr/hyprlock-colors.conf` and
`ghostty/colors`, then reloads Hyprland. Ghostty needs a restart to pick up new colours.
Add `--wallpapers` to rebuild the generated wallpapers from the new palette too (~3s).

`scripts/wallgen` builds five wallpapers — `mesh`, `ridge`, `aurora`, `topo`, `dusk` — into
`hypr/wallpapers/generated/`, all derived from `theme.json`, so the background always belongs
to the same colour world as the shell. Pass style names to rebuild a subset, or
`--size 3840x2160` for a different resolution.

## Scripts

`sysinfo` and `keybinds` back the desktop widgets and cheatsheet. The remaining scripts
(`cpu_temp`, `gpu_temp`, `gpu_util`, `disk_status`, `mem_status.sh`, `network_status`,
`mpris_status`) are the original waybar-era collectors, still used by bar modules for their
rich tooltips.

## Session

`hypridle` (started from `hyprland.lua`) dims at 8 minutes, locks at 15, and turns the screens
off at 17.

The lock screen (`hypr/hyprlock.conf`, `SUPER+End`) is a large thin clock over a blurred
wallpaper, with a rounded card holding an avatar ring, username and password field, plus host,
uptime and now-playing along the bottom. Colours come from the generated
`hyprlock-colors.conf`. Two deliberate choices: nothing is pinned to a monitor name, because
the KVM reshuffles DP ports and pinned elements silently vanish; and the background is the
wallpaper rather than `screenshot`, because a blurred screenshot still leaks whatever was on
screen when the lock engaged.

## Not done yet

- Notification grouping per app
- Popups live 3s (10s for critical); the center keeps them until cleared
- Inline Wi-Fi passphrase entry (currently hands off to `nmtui-connect`)
- `hypr/hyprland.conf` is stale and unused; `hyprland.lua` is the live config
