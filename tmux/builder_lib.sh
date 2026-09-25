#!/usr/bin/env bash
# Shared skeleton for the per-project builders in ~/.tmux/<name>.sh.
# Source this; do not execute it.
#
# The builders were copy-pasted from one another, so every structural change to
# a project had to be chased through eight near-identical files. Everything they
# had in common lives here now; a builder should be a declaration of its windows
# and nothing else.
#
# Deliberately no `set -e`: tmux commands can return non-zero on benign races
# (move-window when the index is already right, for one) and aborting there
# would leave a half-built session behind.
set -uo pipefail

# b_init <session> <dir>
# Creates the session detached with its first window pinned to index 0. Bails
# loudly if the project directory is gone -- a moved or renamed project is the
# single most common way these builders break, and the old silent `cd` failure
# left a half-built session that looked fine until you switched to it.
b_init() {
  NAME=$1
  DIR=$2

  if [ ! -d "$DIR" ]; then
    echo "tmux builder $NAME: project dir missing: $DIR" >&2
    exit 1
  fi

  cd "$DIR" || exit 1

  # new-session lands its window on the ambient base-index (1 here), so pin it
  # to the index this layout wants instead of assuming base-index 0.
  tmux new-session -d -s "$NAME" -n "${3:-claude}" -c "$DIR"
  tmux move-window -d -s "$NAME:^" -t "$NAME:${4:-0}" 2>/dev/null
}

# b_venv [dir]
# Finds the project's virtualenv and exports:
#   VENV_ACTIVATE  the `source .../activate` line, or '' when there is none
#   VENV_PY        absolute path to the venv's python, or '' when there is none
# Checks .venv before venv: narsil moved to a uv-managed .venv and silently lost
# its activation for weeks. Probing both means the next such rename is a no-op
# here instead of another broken session.
b_venv() {
  local dir=${1:-$DIR} candidate
  VENV_ACTIVATE=""
  VENV_PY=""
  for candidate in .venv venv; do
    if [ -f "$dir/$candidate/bin/activate" ]; then
      VENV_ACTIVATE="source $candidate/bin/activate"
      VENV_PY="$dir/$candidate/bin/python"
      return 0
    fi
  done
  return 0
}

# b_send <window-index> <command...>
# Types a command into the window's active pane. Addressed by window rather than
# pane so this does not depend on pane-base-index either.
b_send() {
  local idx=$1; shift
  tmux send-keys -t "$NAME:$idx" "$*" C-m
}

# b_window <index> <name>
b_window() {
  tmux new-window -d -t "$NAME:$1" -n "$2" -c "$DIR"
}

# b_cd <index>
# The `cd` every window opens with. Prepends the venv activation when the
# project has one, so builders never spell out a venv path themselves.
b_cd() {
  if [ -n "${VENV_ACTIVATE:-}" ]; then
    b_send "$1" "cd $DIR && $VENV_ACTIVATE && clear"
  else
    b_send "$1" "cd $DIR && clear"
  fi
}

# b_ssh <index> <window-name> <host> <remote-dir>
# A standing shell on a production box. These are the prod hosts (dagobah,
# alderaan, bespin) -- the homelab boxes are driven by `make deploy` from here
# and intentionally have no window.
b_ssh() {
  b_window "$1" "$2"
  b_send "$1" "cd $DIR && clear && ssh $3"
  b_send "$1" "cd $4 && clear"
}

# b_finish <window-index>
# Select the window to land on, then attach ONLY when stdout is a real terminal.
# The login path (scripts/start_tmux_sessions.sh) runs headless, where attaching
# either fails or blocks forever holding up the rest of startup.
b_finish() {
  tmux select-window -t "$NAME:$1"
  [ -t 1 ] || return 0
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "=$NAME"
  else
    tmux attach -t "=$NAME"
  fi
}
