#!/usr/bin/env bash
# Signals the ptt-dictate daemon to start/stop/toggle recording, or begin
# teach mode (learn a word's spelling). copy-last puts the most recent
# transcription on the clipboard instead; it reads the usage log, so it works
# without the daemon.
# Usage: ptt_dictate.sh start|stop|toggle|teach-start|copy-last
set -euo pipefail

if [[ "${1:-}" == "copy-last" ]]; then
    LOG="$HOME/.local/share/ptt-dictate/history.jsonl"
    text="$(tail -n 1 "$LOG" 2>/dev/null | jq -r '.text // empty')"
    if [[ -z "$text" ]]; then
        notify-send -a ptt-dictate "No transcription yet" "Nothing in $LOG"
        exit 1
    fi
    # text/plain forced, as in the clipboard panel: wl-copy's sniffing can
    # mislabel text and apps like Slack then refuse to paste it
    printf '%s' "$text" | wl-copy --type text/plain
    preview="${text:0:120}"
    [[ ${#text} -gt 120 ]] && preview+="…"
    notify-send -a ptt-dictate "Copied last transcription" "$preview"
    exit 0
fi

PID_FILE="$HOME/.cache/ptt-dictate.pid"

if [[ ! -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    notify-send -a ptt-dictate -u critical "ptt-dictate daemon not running" \
        "start it: systemctl --user start ptt-dictate"
    exit 1
fi

PID="$(cat "$PID_FILE")"

case "${1:-}" in
    start)       kill -USR1 "$PID" ;;
    stop)        kill -USR2 "$PID" ;;
    toggle)      kill -RTMIN "$PID" ;;
    teach-start) kill -RTMIN+1 "$PID" ;;
    *) echo "usage: $0 start|stop|toggle|teach-start|copy-last" >&2; exit 1 ;;
esac
