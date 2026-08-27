#!/usr/bin/env bash
# Create every autostart=yes session from ~/.tmux/sessions.list, detached.
# Called from the Hyprland autostart block in hypr/hyprland.lua.
#
# Runs headless: it must never attach and never block. Existing sessions are
# left completely alone.
set -euo pipefail

. "$HOME/.tmux/sessions_lib.sh"

# Builders use `tmux new-session -d`, which starts the server if needed.
while IFS=$'\t' read -r key session builder auto; do
  [ "$auto" = "yes" ] || continue
  if session_exists "$session"; then
    echo "tmux: $session already running"
    continue
  fi
  echo "tmux: creating $session"
  ensure_session "$session" || echo "tmux: FAILED to create $session" >&2
done < <(sessions_each)
