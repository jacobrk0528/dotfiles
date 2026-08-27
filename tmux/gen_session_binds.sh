#!/usr/bin/env bash
# Derives the per-session jump binds from sessions.list and applies them to the
# running server. Invoked by tmux.conf via run-shell, so it must talk to tmux
# directly rather than printing config (run-shell output is not parsed as config).
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/sessions_lib.sh"

GOTO="$TMUX_DIR/goto.sh"
CHEAT="${XDG_RUNTIME_DIR:-/tmp}/tmux-session-keys.txt"

{
  echo "Session jump keys"
  echo
} > "$CHEAT"

while IFS=$'\t' read -r key session builder auto; do
  [ "$key" = "-" ] && continue
  tmux bind-key "$key" run-shell "$GOTO $session"
  printf '  C-a %-5s %s\n' "$key" "$session" >> "$CHEAT"
done < <(sessions_each)

cat >> "$CHEAT" <<'EOF'

  C-a f     fzf session picker
  C-a Tab   last session
  C-a h / l previous / next session
  C-a S     this cheatsheet

Missing sessions are built from ~/.tmux/<builder>.sh on demand.
EOF

# 'S' is free; leave '?' to tmux's own list-keys.
# Run the body under bash explicitly: tmux uses default-shell (zsh here), and
# `read -rsn1` is bash syntax that zsh rejects outright, so the popup would
# error out and close before it could be read.
tmux bind-key S display-popup -E "bash -c \"cat '$CHEAT'; echo; echo '  press any key to close'; read -rsn1\""
