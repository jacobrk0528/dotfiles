#!/usr/bin/env bash
# Create a session if missing, then attach to it -- but ONLY attach when stdout
# is a real terminal. The login/autostart path runs headless, where `tmux attach`
# either fails or blocks forever holding up the rest of startup.
#
#   load_or_create.sh <session>            interactive: create if needed, attach
#   load_or_create.sh --detach <session>   never attach (startup path)
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/sessions_lib.sh"

DETACH_ONLY=0
if [ "${1:-}" = "--detach" ] || [ "${1:-}" = "-d" ]; then
  DETACH_ONLY=1
  shift
fi

if [ -z "${1:-}" ]; then
  echo "Usage: ~/.tmux/load_or_create.sh [--detach] <session_name>" >&2
  exit 1
fi

NAME=$(resolve_name "$1")

ensure_session "$NAME"

if [ "$DETACH_ONLY" -eq 1 ] || [ ! -t 1 ]; then
  exit 0
fi

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "=$NAME"
else
  tmux attach -t "=$NAME"
fi
