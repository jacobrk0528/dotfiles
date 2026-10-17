#!/usr/bin/env bash
# Builder for the "agents" hub: a sidebar listing every Claude Code pane in
# tmux (left) beside a nested client that shows the picked one (right). See
# scripts/agents/README.md.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

AGENTS="$HOME/dotfiles/scripts/agents/agents"

b_init agents "$HOME" hub 0

SIDEBAR=$(tmux display -p -t "$NAME:0" '#{pane_id}')
tmux split-window -h -d -t "$NAME:0" -c "$HOME" "$AGENTS --viewer"
# tmux scales panes proportionally on resize; pin the sidebar's width instead.
tmux resize-pane -t "$SIDEBAR" -x 36
tmux set-hook -t "$NAME" client-resized "resize-pane -t $SIDEBAR -x 36"
tmux set-hook -t "$NAME" client-attached "resize-pane -t $SIDEBAR -x 36"
tmux set-hook -t "$NAME" client-session-changed "resize-pane -t $SIDEBAR -x 36"
b_send 0 "clear && $AGENTS --sidebar"

b_finish 0
