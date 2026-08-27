#!/usr/bin/env bash
# Builder for the "dotfiles" session. Previously this was created inline by
# scripts/start_tmux_sessions.sh; it lives here so every entry in
# sessions.list resolves the same way.
set -euo pipefail

DIR="$HOME/dotfiles"
NAME="dotfiles"

# new-session lands its window on the ambient base-index (1 here), so pin it to
# the index this layout wants instead of assuming base-index 0.
tmux new-session -d -s "$NAME" -n claude -c "$DIR"
tmux move-window -d -s "$NAME:^" -t "$NAME:0" 2>/dev/null

tmux send-keys -t "$NAME:0" "clear" C-m
tmux send-keys -t "$NAME:0" "claude" C-m

tmux new-window -d -t "$NAME:1" -n nvim -c "$DIR"
tmux send-keys -t "$NAME:1" "nvim ." C-m
