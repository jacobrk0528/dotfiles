#!/usr/bin/env bash
# Jump to a session, creating it from its builder first if it is missing, so a
# jump key never errors out. Bound to prefix <key> via gen_session_binds.sh.
set -euo pipefail

# shellcheck source=sessions_lib.sh
. "$(dirname "$(readlink -f "$0")")/sessions_lib.sh"

[ $# -ge 1 ] || { echo "Usage: goto.sh <session>" >&2; exit 1; }

NAME=$(resolve_name "$1")

if ! session_exists "$NAME"; then
  tmux display-message "creating $NAME..." 2>/dev/null || true
  ensure_session "$NAME"
fi

if [ -z "${TMUX:-}" ] && [ ! -t 1 ]; then
  exit 0                                  # headless: creating was the whole job
fi

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "=$NAME"
else
  tmux attach -t "=$NAME"
fi
