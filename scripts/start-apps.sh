#!/usr/bin/env bash
# Launch the session's apps and put each window where it belongs.
#
# Why this exists rather than `exec` workspace hints in hyprland.lua:
#
#  1. A hint arms a rule for the NEXT window that maps, not for the process
#     being launched. Slack and Chrome take seconds while ghostty is instant,
#     so the rules land on the wrong windows.
#  2. Far worse: a *visible* special workspace captures every window opened
#     afterwards. launch_logs.sh's windows are rule-assigned to special:logs,
#     which leaves it showing, so Slack, Chrome and the terminal all opened
#     inside the logs scratchpad.
#
# So: launch the log windows first, hide the scratchpads, launch everything
# else with a precise class match and move each window explicitly, then sweep
# once more at the end to catch anything that slipped through.

set -uo pipefail

LOG=/tmp/start-apps.log
TIMEOUT=30

exec 2>>"$LOG"
echo "=== start-apps $(date -Is) ===" >>"$LOG"

log() { echo "$(date +%H:%M:%S) $*" >>"$LOG"; }

# Addresses of windows matching a class regex and an optional title regex.
matching() {
    hyprctl clients -j | python3 -c '
import json, re, sys
class_re, title_re = sys.argv[1], sys.argv[2]
for c in json.load(sys.stdin):
    if not re.search(class_re, c.get("class", "")):
        continue
    if title_re and not re.search(title_re, c.get("title", "")):
        continue
    print(c["address"])
' "$1" "${2:-}"
}

move_to() {
    hyprctl dispatch \
        "hl.dsp.window.move({ workspace = \"$1\", window = \"address:$2\", silent = true })" \
        >/dev/null
}

# A visible scratchpad swallows every window opened while it is up.
hide_specials() {
    hyprctl monitors -j | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    name = m["specialWorkspace"]["name"]
    if name:
        print(name.removeprefix("special:"))
' | while read -r s; do
        [ -n "$s" ] && log "hiding special:$s" && \
            hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$s\")" >/dev/null
    done
}

# Like launch_to, but moves EVERY window that appeared, not just the first.
# Chrome restores a profile's previous session alongside the window you asked
# for, so a personal profile can map two windows at once.
launch_all_to() {
    local ws="$1" class_re="$2" title_re="$3"
    shift 3

    local before waited=0 new=""
    before=$(matching "$class_re" "$title_re" | sort)

    setsid "$@" >/dev/null 2>&1 &

    while [ "$waited" -lt "$TIMEOUT" ]; do
        sleep 0.5
        waited=$((waited + 1))
        new=$(comm -13 <(printf '%s\n' "$before") <(matching "$class_re" "$title_re" | sort) | grep -v '^$')
        [ -n "$new" ] && break
    done

    # Give a restored session a moment to map its own windows too.
    sleep 3
    new=$(comm -13 <(printf '%s\n' "$before") <(matching "$class_re" "$title_re" | sort) | grep -v '^$')

    if [ -z "$new" ]; then
        log "TIMEOUT waiting for $class_re ${title_re:+($title_re)}"
        return 1
    fi

    printf '%s\n' "$new" | while read -r addr; do
        log "moving $class_re -> $ws ($addr)"
        move_to "$ws" "$addr"
    done
}

# launch_to <workspace> <class regex> <title regex|""> <command...>
launch_to() {
    local ws="$1" class_re="$2" title_re="$3"
    shift 3

    local before waited=0 new=""
    before=$(matching "$class_re" "$title_re" | sort)

    setsid "$@" >/dev/null 2>&1 &

    while [ "$waited" -lt "$TIMEOUT" ]; do
        sleep 0.5
        waited=$((waited + 1))
        new=$(comm -13 <(printf '%s\n' "$before") <(matching "$class_re" "$title_re" | sort) \
              | grep -v '^$' | head -n1)
        [ -n "$new" ] && break
    done

    if [ -z "$new" ]; then
        log "TIMEOUT waiting for $class_re ${title_re:+($title_re)}"
        return 1
    fi

    log "moving $class_re -> $ws ($new)"
    move_to "$ws" "$new"
}

# ── Phase 1: log windows, which are rule-assigned to special:logs ──────
"$HOME/.config/hypr/scripts/launch_logs.sh" &
sleep 3
hide_specials

# ── Phase 2: everything else, in parallel ─────────────────────────────
# Distinct --class values: matching bare "ghostty" would collide with btop and
# with the two log windows.
launch_to "special:slack" '^slack$' "" slack &
launch_to "special:btop" '^com\.jkrebs\.btop$' "" \
    ghostty --class=com.jkrebs.btop --title=btop -e bash -c btop &
launch_to "2" '^com\.jkrebs\.term$' "" ghostty --class=com.jkrebs.term &
# Chrome, twice: workspaces 3 and 1, both on the new tab page, both in the
# Default profile (jkrebs@trinityroad.com). Naming the profile skips the
# "Who's using Chrome?" picker, which is still what a manual launch gets.
# The systemd scope caps Chrome's memory — see the `browser` comment in
# hyprland.lua for why. Only the first launch needs it: the second joins the
# already-running process, and therefore the same cgroup.
# Serialised, because all three share the google-chrome window class and two
# in flight at once could not be told apart.
(
    launch_to "3" '^google-chrome$' "" bash -c \
        'systemd-run --user --scope --collect -p MemoryHigh=8G -p MemoryMax=24G -- google-chrome-stable --profile-directory=Default --new-window "chrome://newtab" --js-flags="--max-old-space-size=4096"'
    launch_to "1" '^google-chrome$' "" \
        google-chrome-stable --profile-directory=Default --new-window "chrome://newtab"
    # Personal profile. launch_all_to because this profile restores a session,
    # so it maps its old windows alongside the new tab.
    launch_all_to "5" '^google-chrome$' "" \
        google-chrome-stable --profile-directory="Profile 1" --new-window "chrome://newtab"
) &
wait

# ── Phase 3: sweep ────────────────────────────────────────────────────
# A window can still be captured if it maps while a scratchpad is briefly up.
# Chrome is deliberately absent: its two windows are on different workspaces,
# so a class-wide sweep would drag them both to the same one.
sweep() {
    local ws="$1" class_re="$2" title_re="${3:-}"
    matching "$class_re" "$title_re" | while read -r addr; do
        local at
        at=$(hyprctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["address"] == sys.argv[1]:
        print(c["workspace"]["name"])
' "$addr")
        if [ "$at" != "$ws" ]; then
            log "sweep: $class_re on $at -> $ws"
            move_to "$ws" "$addr"
        fi
    done
}

sleep 3
sweep "special:slack" '^slack$'
sweep "special:btop" '^com\.jkrebs\.btop$'
sweep "special:logs" 'ghostty' '_log$'

hide_specials
log "done"
exit 0
