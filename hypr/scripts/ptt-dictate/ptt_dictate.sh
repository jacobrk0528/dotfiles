#!/usr/bin/env bash
# Signals the ptt-dictate daemon to start/stop/toggle recording, or begin
# teach mode (learn a word's spelling).
# Usage: ptt_dictate.sh start|stop|toggle|teach-start
set -euo pipefail

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
    *) echo "usage: $0 start|stop|toggle|teach-start" >&2; exit 1 ;;
esac
